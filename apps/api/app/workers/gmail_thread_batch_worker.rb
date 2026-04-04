# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param access_token [String] Google OAuth access token
  # @param thread_ids   [Array<String>] thread IDs to fetch
  def perform(access_token, thread_ids)
    GmailThreadBatchFetcher.new(
      access_token:
    ).call(thread_ids)
  end
end
