# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param token_key  [String] UUID key issued by AccessTokenStore#store
  # @param after_date [String, nil] ISO 8601 date string (e.g. "2024-01-01")
  def perform(token_key, after_date)
    access_token = AccessTokenStore.new.fetch(token_key)
    query        = IngressDamageReportQuery.new(after_date:)
    thread_ids   = GmailThreadListFetcher.new(access_token:).call(q: query.to_s)

    return if thread_ids.empty?

    SqsClient.new(Settings.sqs_report_queue_url)
             .send_messages(thread_ids, attributes: { AccessTokenStore::TOKEN_KEY_ATTR => token_key })
  end
end
