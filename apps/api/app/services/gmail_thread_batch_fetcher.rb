# frozen_string_literal: true

# Fetches full Gmail thread data for the given thread IDs using the Batch API.
#
# Designed to be called from a Sidekiq Worker.
# Automatically chunks IDs to respect the Gmail Batch API limit (100 per request).
#
# @example
#   threads = GmailThreadBatchFetcher.new(
#     access_token: token
#   ).call(["id1", "id2", "id3"])
class GmailThreadBatchFetcher
  BATCH_SIZE = 100

  def initialize(access_token:, gmail_client: nil)
    @gmail_client = gmail_client || GmailClient.new(access_token, redis: REDIS)
  end

  # @param thread_ids [Array<String>]
  # @return [Array<GmailMessage>] all messages across all threads, in thread order
  def call(thread_ids)
    return [] if thread_ids.empty?

    thread_ids.each_slice(BATCH_SIZE).flat_map do |batch|
      @gmail_client.batch_get_threads(batch).flat_map do |raw|
        next [] if raw.nil?
        (raw["messages"] || []).map { |m| GmailMessage.new(m) }
      end
    end
  end
end
