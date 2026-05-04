# frozen_string_literal: true

require "net/http"
require "json"

module GoogleTokenHelper
  TOKEN_URI = URI("https://oauth2.googleapis.com/token")

  # Exchange a refresh token for a fresh access token.
  # Reads credentials from environment variables so that no refresh-token
  # handling ever appears in production code.
  #
  # Required env vars:
  #   GOOGLE_TEST_REFRESH_TOKEN - long-lived refresh token (GitHub Actions secret)
  #   GOOGLE_CLIENT_ID          - OAuth client ID
  #   GOOGLE_CLIENT_SECRET      - OAuth client secret
  def fetch_google_access_token
    response = Net::HTTP.post_form(TOKEN_URI, {
      grant_type:    "refresh_token",
      refresh_token: ENV.fetch("GOOGLE_TEST_REFRESH_TOKEN"),
      client_id:     ENV.fetch("GOOGLE_CLIENT_ID"),
      client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"),
    })
    body = JSON.parse(response.body)
    body.fetch("access_token") do
      raise "Google token exchange failed (HTTP #{response.code}): #{response.body}"
    end
  end
end
