# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param access_token [String] Google OAuth access token
  # @param after_date   [String, nil] ISO 8601 date string (e.g. "2024-01-01")
  def perform(access_token, after_date)
    query      = IngressDamageReportQuery.new(after_date:)
    thread_ids = GmailThreadListFetcher.new(access_token:).call(q: query.to_s)

    return if thread_ids.empty?

    SqsClient.new(Settings.sqs_report_queue_url).send_messages(thread_ids)
  end
end
