# frozen_string_literal: true

# Stores Google OAuth access tokens. Expires after TTL matching Google's token lifetime.
# A new login overwrites the previous token, enforcing one active token per user.
class AccessTokenStore < UserStore
  KEY_PREFIX = "access_token"
  TTL        = 3600 # seconds — matches Google OAuth access token lifetime
end
