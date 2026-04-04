# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param access_token [String] Google OAuth access token
  # @param after_date   [String] ISO 8601 date string (e.g. "2024-01-01")
  #                              before_date is set to one year after after_date
  def perform(access_token, after_date)
    query      = build_query(after_date)
    thread_ids = GmailThreadListFetcher.new(access_token:).call(q: query.to_s)

    return if thread_ids.empty?

    tasks = thread_ids.map { |id| ReportTask.new(thread_id: id) }
    SqsClient.new(ENV.fetch("SQS_REPORT_QUEUE_URL")).send_messages(tasks)
  end

  private

  def build_query(after_date)
    after  = Date.parse(after_date || "2012-10-15")
    before = after >> 12
    GmailSearchQuery.new(
      subject: "Ingress Damage Report: Entities attacked by",
      after_date: after,
      before_date: before,
      from: ["ingress-support@google.com", "ingress-support@nianticlabs.com", "ingress-support@nianticspatial.com"],
      smaller: "200K"
    )
  end
end
