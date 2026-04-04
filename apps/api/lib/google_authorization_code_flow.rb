# frozen_string_literal: true

require "oauth2"

class GoogleAuthorizationCodeFlow
  AUTHORIZATION_URL = "https://accounts.google.com/o/oauth2/auth"
  TOKEN_URL = "https://oauth2.googleapis.com/token"

  def self.authorization_url(redirect_uri:, scope:, state: nil)
    params = {
      redirect_uri: redirect_uri,
      scope: scope,
      access_type: "online",
      include_granted_scopes: "true",
      state: state
    }.compact

    client.auth_code.authorize_url(**params)
  end

  def self.fetch(code:, redirect_uri:)
    client.auth_code.get_token(code, redirect_uri: redirect_uri).token
  rescue OAuth2::Error => e
    raise FetchError, "Failed to fetch access token: #{e.description}"
  end

  class FetchError < StandardError; end

  class << self
    private

    def client
      OAuth2::Client.new(
        Rails.application.credentials.dig(:google, :client_id),
        Rails.application.credentials.dig(:google, :client_secret),
        authorize_url: AUTHORIZATION_URL,
        token_url: TOKEN_URL
      )
    end
  end
end
