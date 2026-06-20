# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param user_id    [String] Google account ID
  # @param after_date [Integer, nil] Unix epoch (e.g. Time.utc(2024, 1, 1).to_i)
  def perform(user_id, after_date)
    access_token  = UserStore.access_token.fetch(user_id)
    fetcher       = GmailThreadListFetcher.new(access_token:)
    current_epoch = after_date || DamageReportQuery::DEFAULT_AFTER_DATE
    total_count   = 0
    sqs           = SqsClient.new(Settings.sqs_thread_ids_queue_url)

    loop do
      before_epoch = current_epoch + DamageReportQuery::DAYS_WINDOW * 24 * 3_600
      query        = DamageReportQuery.new(after_date: current_epoch, before_date: before_epoch)

      logger.debug "query: #{query}"
      window_ids = fetcher.call(q: query.to_s)
      logger.debug "found #{window_ids.size} threads in window starting #{current_epoch}"

      # Count threads_found before enqueuing the window's slices so the counter
      # always covers every message already in SQS. Otherwise the batch worker
      # could process a message before threads_found includes it, momentarily
      # making threads_processed reach threads_found and prematurely marking the
      # run complete. The counter is reset to 0 at sync start.
      UserStore.threads_found.increment(user_id, by: window_ids.size) if window_ids.any?
      window_ids.sort.each_slice(Settings.thread_list_worker_threads_per_message) do |slice|
        sqs.send_messages(slice, attributes: { UserStore::USER_ID_ATTR => user_id })
      end
      total_count += window_ids.size

      break if total_count > Settings.thread_list_worker_thread_id_limit
      break if before_epoch >= Time.now.to_i

      current_epoch = before_epoch
    end

    logger.debug "sent #{total_count} thread_ids to SQS"
  end
end
