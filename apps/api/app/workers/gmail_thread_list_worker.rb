# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param user_id    [String] Google account ID
  # @param after_date [Integer, nil] Unix epoch (e.g. Time.utc(2024, 1, 1).to_i)
  def perform(user_id, after_date)
    access_token  = UserStore.access_token.fetch(user_id)
    fetcher       = GmailThreadListFetcher.new(access_token:)
    current_epoch = after_date || IngressDamageReportQuery::DEFAULT_AFTER_DATE
    thread_ids    = []

    loop do
      query      = IngressDamageReportQuery.new(after_date: current_epoch)
      logger.debug "query: #{query}"
      thread_ids = fetcher.call(q: query.to_s)
      logger.debug "found #{thread_ids.size} threads for after_date=#{current_epoch}"

      break if thread_ids.any?
      break unless after_date.nil?

      next_date = Time.at(current_epoch).utc.to_date >> IngressDamageReportQuery::MONTHS_RANGE
      break if next_date > Date.today

      current_epoch = Time.utc(next_date.year, next_date.month, next_date.day).to_i
    end

    UserStore.threads_found.store(user_id, thread_ids.size.to_s)

    if thread_ids.empty?
      logger.debug "no threads found, skipping SQS"
      return
    end

    sqs = SqsClient.new(Settings.sqs_thread_ids_queue_url)
    thread_ids.each_slice(Settings.thread_list_worker_threads_per_message) do |slice|
      sqs.send_messages(slice, attributes: { UserStore::USER_ID_ATTR => user_id })
    end
    logger.debug "sent #{thread_ids.size} thread_ids to SQS"
  end
end
