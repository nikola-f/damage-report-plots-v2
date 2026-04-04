# frozen_string_literal: true

class GmailThreadListWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3

  # @param user_id      [String]
  # @param email        [String]
  # @param access_token [String] Google OAuth access token
  # @param q            [String, nil] Gmail search query
  def perform(user_id, email, access_token, q = nil)
    GmailThreadListFetcher.new(
      access_token:,
      user_id:,
      email:
    ).call(q:)
  end
end
