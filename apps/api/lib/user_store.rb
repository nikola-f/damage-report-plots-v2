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

  def self.last_synced_at(redis: REDIS)
    new(prefix: "last_synced_at", redis:)
  end

  # Server time (Unix epoch, seconds) of the most recent processed batch
  # message, advanced only forward. Its final value after a sync run
  # approximates when the workflow finished.
  def self.last_processed_at(redis: REDIS)
    new(prefix: "last_processed_at", redis:)
  end

  def self.scope_spreadsheets(redis: REDIS)
    new(prefix: "scope_spreadsheets", ttl: 3600, redis:)
  end

  def self.scope_sync(redis: REDIS)
    new(prefix: "scope_sync", ttl: 3600, redis:)
  end

  def self.threads_found(redis: REDIS)
    new(prefix: "threads_found", redis:)
  end

  def self.threads_processed(redis: REDIS)
    new(prefix: "threads_processed", redis:)
  end

  def self.portals_found(redis: REDIS)
    new(prefix: "portals_found", redis:)
  end

  def self.portals_appended(redis: REDIS)
    new(prefix: "portals_appended", redis:)
  end

  def self.threads_max_internal_date(redis: REDIS)
    new(prefix: "threads_max_internal_date", redis:)
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
  # @param by      [Integer]
  def increment(user_id, by: 1)
    @redis.incrby(redis_key(user_id), by)
  end

  # @param user_id [String] Google account ID
  # @return [String]
  # @raise [KeyError] if not found
  def fetch(user_id)
    value = @redis.get(redis_key(user_id))
    raise KeyError, "#{@prefix} not found for user" unless value

    value
  end

  # @param user_id [String] Google account ID
  # @return [Integer] number of keys removed (0 if it did not exist)
  def delete(user_id)
    @redis.del(redis_key(user_id))
  end

  private

  def redis_key(user_id) = "#{@prefix}:#{user_id}"
end
