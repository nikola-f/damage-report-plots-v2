# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param access_token [String] Google OAuth access token
  # @param q            [String, nil] Gmail search query
  def perform(access_token, q = nil)
    thread_ids = GmailThreadListFetcher.new(access_token:).call(q:)

    return if thread_ids.empty?

    tasks = thread_ids.map { |id| ReportTask.new(thread_id: id) }
    SqsClient.new(ENV.fetch("SQS_REPORT_QUEUE_URL")).send_messages(tasks)
  end
end
