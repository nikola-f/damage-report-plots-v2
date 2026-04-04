# frozen_string_literal: true

# Fetches all Gmail thread IDs matching a query.
#
# Designed to be called from a Sidekiq Worker (not from a request cycle).
# Handles Gmail pagination internally — all pages are fetched before returning.
#
# @example
#   thread_ids = GmailThreadListFetcher.new(
#     access_token: token
#   ).call(q: "subject:damage report after:2024/01/01")
class GmailThreadListFetcher
  def initialize(access_token:, gmail_client: nil)
    @gmail_client = gmail_client || GmailClient.new(access_token, redis: REDIS)
  end

  # @param q [String, nil] Gmail search query
  # @return [Array<String>] thread IDs
  def call(q: nil)
    fetch_all_threads(q:).map { |thread| thread["id"] }
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
