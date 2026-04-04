# frozen_string_literal: true

# Fetches all Gmail threads matching a query and returns them as ReportTask objects.
#
# Designed to be called from a Sidekiq Worker (not from a request cycle).
# Handles Gmail pagination internally — all pages are fetched before returning.
#
# @example
#   tasks = GmailThreadListFetcher.new(
#     access_token: token,
#     user_id:      "user_001",
#     email:        "user@example.com"
#   ).call(q: "subject:damage report after:2024/01/01")
class GmailThreadListFetcher
  def initialize(access_token:, user_id:, email:, gmail_client: nil)
    @user_id      = user_id
    @email        = email
    @gmail_client = gmail_client || GmailClient.new(access_token, user_id: user_id, redis: REDIS)
  end

  # @param q [String, nil] Gmail search query
  # @return [Array<ReportTask>]
  def call(q: nil)
    fetch_all_threads(q:).map do |thread|
      ReportTask.new(thread_id: thread["id"], user_id: @user_id, email: @email)
    end
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
