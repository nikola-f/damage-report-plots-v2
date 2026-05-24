# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  THREAD_IDS_CHUNK_SIZE = 10 * 1024

  # @param user_id    [String] Google account ID
  # @param after_date [String, nil] ISO 8601 date string (e.g. "2024-01-01")
  def perform(user_id, after_date)
    access_token = UserStore.access_token.fetch(user_id)

    query = IngressDamageReportQuery.new(after_date:)
    logger.debug "query: #{query}"

    thread_ids = GmailThreadListFetcher.new(access_token:).call(q: query.to_s)
    logger.debug "found #{thread_ids.size} threads"

    if thread_ids.empty?
      logger.debug "no threads found, skipping SQS"
      return
    end

    SqsClient.new(Settings.sqs_thread_ids_queue_url)
             .send_messages(thread_ids,
                            attributes: { UserStore::USER_ID_ATTR => user_id },
                            max_message_size: THREAD_IDS_CHUNK_SIZE)
    logger.debug "sent #{thread_ids.size} thread_ids to SQS"
  end
end
