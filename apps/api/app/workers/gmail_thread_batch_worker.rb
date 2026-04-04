# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param user_id      [String]
  # @param access_token [String] Google OAuth access token
  # @param thread_ids   [Array<String>] thread IDs to fetch
  def perform(user_id, access_token, thread_ids)
    GmailThreadBatchFetcher.new(
      access_token:,
      user_id:
    ).call(thread_ids)
  end
end
