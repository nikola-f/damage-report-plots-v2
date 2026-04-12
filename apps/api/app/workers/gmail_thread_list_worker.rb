# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param user_id    [String] Google account ID
  # @param after_date [String, nil] ISO 8601 date string (e.g. "2024-01-01")
  def perform(user_id, after_date)
    access_token = UserStore.access_token.fetch(user_id)
    query        = IngressDamageReportQuery.new(after_date:)
    thread_ids   = GmailThreadListFetcher.new(access_token:).call(q: query.to_s)

    return if thread_ids.empty?

    SqsClient.new(Settings.sqs_report_queue_url)
             .send_messages(thread_ids, attributes: { UserStore::USER_ID_ATTR => user_id })
  end
end
