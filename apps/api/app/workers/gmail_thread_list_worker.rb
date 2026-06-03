# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param user_id    [String] Google account ID
  # @param after_date [String, nil] ISO 8601 date string (e.g. "2024-01-01")
  def perform(user_id, after_date)
    access_token = UserStore.access_token.fetch(user_id)

    query = IngressDamageReportQuery.new(after_date:)
    logger.debug "query: #{query}"

    thread_ids = GmailThreadListFetcher.new(access_token:).call(q: query.to_s)
    logger.debug "found #{thread_ids.size} threads"
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
