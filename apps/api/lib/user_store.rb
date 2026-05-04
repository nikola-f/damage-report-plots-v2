# frozen_string_literal: true

# Redis store keyed by user_id (Google account ID).
# Use factory methods to obtain pre-configured instances.
class UserStore
  USER_ID_ATTR = "user_id" # SQS message attribute name for passing user IDs between workers

  def self.access_token(redis: REDIS)
    new(prefix: "access_token", ttl: 3600, redis:)
  end

  def self.spreadsheet_id(redis: REDIS)
    new(prefix: "spreadsheet_id", redis:)
  end

  def initialize(prefix:, ttl: nil, redis: REDIS)
    @prefix = prefix
    @ttl    = ttl
    @redis  = redis
  end

  # @param user_id [String] Google account ID
  # @param value   [String]
  def store(user_id, value)
    opts = @ttl ? { ex: @ttl } : {}
    @redis.set(redis_key(user_id), value, **opts)
  end

  # @param user_id [String] Google account ID
  # @return [String]
  # @raise [KeyError] if not found
  def fetch(user_id)
    value = @redis.get(redis_key(user_id))
    raise KeyError, "#{@prefix} not found for user" unless value

    value
  end

  private

  def redis_key(user_id) = "#{@prefix}:#{user_id}"
end
