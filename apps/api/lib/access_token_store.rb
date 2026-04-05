# frozen_string_literal: true

# Stores OAuth access tokens in Redis for secure handoff to background jobs.
# Avoids passing tokens as Sidekiq job arguments (which are stored in plain text).
# Tokens are one-time-use: fetched and deleted atomically via GETDEL.
#
# @example Storing a token before enqueuing a job
#   key = AccessTokenStore.new.store(access_token)
#   GmailThreadListWorker.perform_async(key, after_date)
#
# @example Retrieving the token inside the job
#   access_token = AccessTokenStore.new.fetch_and_delete(key)
class AccessTokenStore
  TTL        = 3600 # seconds — matches Google OAuth access token lifetime
  KEY_PREFIX = "access_token"

  def initialize(redis: REDIS)
    @redis = redis
  end

  # Stores an access token and returns the reference key.
  # @param access_token [String]
  # @return [String] UUID key to pass to the background job
  def store(access_token)
    key = SecureRandom.uuid
    @redis.set(redis_key(key), access_token, ex: TTL)
    key
  end

  # Retrieves and atomically deletes the token (one-time-use).
  # @param key [String] UUID returned by #store
  # @return [String] the access token
  # @raise [KeyError] if the token is not found or has expired
  def fetch_and_delete(key)
    token = @redis.getdel(redis_key(key))
    raise KeyError, "Access token not found or expired: #{key}" unless token

    token
  end

  private

  def redis_key(key)
    "#{KEY_PREFIX}:#{key}"
  end
end
