# frozen_string_literal: true

# Base class for Redis stores keyed by user_id (Google account ID).
# Subclasses declare KEY_PREFIX and TTL to configure their storage behaviour.
class UserStore
  USER_ID_ATTR = "user_id" # SQS message attribute name for passing user IDs between workers

  def initialize(redis: REDIS)
    @redis = redis
  end

  # @param user_id [String] Google account ID
  # @param value   [String]
  def store(user_id, value)
    opts = self.class::TTL ? { ex: self.class::TTL } : {}
    @redis.set(redis_key(user_id), value, **opts)
  end

  # @param user_id [String] Google account ID
  # @return [String]
  # @raise [KeyError] if not found
  def fetch(user_id)
    value = @redis.get(redis_key(user_id))
    raise KeyError, "#{self.class::KEY_PREFIX} not found: #{user_id}" unless value

    value
  end

  private

  def redis_key(user_id) = "#{self.class::KEY_PREFIX}:#{user_id}"
end
