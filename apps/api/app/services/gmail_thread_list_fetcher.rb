# frozen_string_literal: true

# Fetches all Gmail threads matching a query and enqueues each as a ReportTask to SQS.
#
# Designed to be called from a Sidekiq Worker (not from a request cycle).
# Handles Gmail pagination internally — all pages are fetched before enqueuing.
#
# @example
#   GmailThreadListFetcher.new(
#     access_token: token,
#     user_id:      "user_001",
#     email:        "user@example.com"
#   ).call(q: "subject:damage report after:2024/01/01")
class GmailThreadListFetcher
  def initialize(access_token:, user_id:, email:, gmail_client: nil, sqs_client: nil)
    @user_id      = user_id
    @email        = email
    @gmail_client = gmail_client || GmailClient.new(access_token, user_id: user_id, redis: REDIS)
    @sqs_client   = sqs_client   || SqsClient.new(ENV.fetch("SQS_REPORT_QUEUE_URL"))
  end

  # @param q [String, nil] Gmail search query
  # @return [Array<Aws::SQS::Types::SendMessageBatchResult>, Array] empty array if no threads found
  def call(q: nil)
    tasks = fetch_all_threads(q:).map do |thread|
      ReportTask.new(thread_id: thread["id"], user_id: @user_id, email: @email)
    end

    return [] if tasks.empty?

    @sqs_client.send_messages(tasks)
  end

  private

  def fetch_all_threads(q:)
    threads    = []
    page_token = nil

    loop do
      response   = @gmail_client.list_threads(q:, page_token:)
      threads.concat(response["threads"] || [])
      page_token = response["nextPageToken"]
      break unless page_token
    end

    threads
  end
end
