# frozen_string_literal: true

# Stores OAuth access tokens in Redis for secure handoff to background jobs.
# Avoids passing tokens as Sidekiq job arguments (which are stored in plain text).
# Tokens expire automatically after TTL (matching Google OAuth access token lifetime).
# Keyed by user_id (Google account ID) — a new login overwrites the previous token,
# enforcing a single active token per user.
#
# @example Storing a token after OAuth callback
#   AccessTokenStore.new.store(user_id, access_token)
#
# @example Retrieving the token inside a job
#   access_token = AccessTokenStore.new.fetch(user_id)
class AccessTokenStore
  TTL        = 3600 # seconds — matches Google OAuth access token lifetime
  KEY_PREFIX = "access_token"

  def initialize(redis: REDIS)
    @redis = redis
  end

  # Stores an access token keyed by user_id. Overwrites any existing token.
  # @param user_id       [String] Google account ID
  # @param access_token  [String]
  def store(user_id, access_token)
    @redis.set(redis_key(user_id), access_token, ex: TTL)
  end

  # Retrieves the token without deleting it (multiple workers can reuse the same key).
  # @param user_id [String] Google account ID
  # @return [String] the access token
  # @raise [KeyError] if the token is not found or has expired
  def fetch(user_id)
    token = @redis.get(redis_key(user_id))
    raise KeyError, "Access token not found or expired: #{user_id}" unless token

    token
  end

  # Retrieves and atomically deletes the token (one-time-use).
  # @param user_id [String] Google account ID
  # @return [String] the access token
  # @raise [KeyError] if the token is not found or has expired
  def fetch_and_delete(user_id)
    token = @redis.getdel(redis_key(user_id))
    raise KeyError, "Access token not found or expired: #{user_id}" unless token

    token
  end

  private

  def redis_key(key)
    "#{KEY_PREFIX}:#{key}"
  end
end
