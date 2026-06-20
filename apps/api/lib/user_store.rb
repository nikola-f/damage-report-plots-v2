# frozen_string_literal: true

# Redis store keyed by user_id (Google account ID).
# Use the generated factory methods (one per STORES key) to obtain instances.
class UserStore
  USER_ID_ATTR = "user_id" # SQS message attribute name for passing user IDs between workers

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

  # @param user_id [String] Google account ID
  # @return [Integer] number of keys removed (0 if it did not exist)
  def delete(user_id)
    @redis.del(redis_key(user_id))
  end

  private

  def redis_key(user_id) = "#{@prefix}:#{user_id}"

  # Value store that additionally supports Redis INCRBY counters. Kept separate
  # from the base store so value stores (access_token, etc.) raise NoMethodError
  # if #increment is mistakenly called on them.
  class CounterStore < UserStore
    # @param user_id [String] Google account ID
    # @param by      [Integer]
    # @return [Integer] the new total after INCRBY
    def increment(user_id, by: 1)
      @redis.incrby(redis_key(user_id), by)
    end
  end

  # prefix => options. ttl in seconds (nil = no expiry); counter: true selects
  # CounterStore. Each key generates a same-named factory method below.
  STORES = {
    access_token:              { ttl: 3600 }, # Google access token (matches token lifetime)
    spreadsheet_id:            {},
    last_synced_at:            {},
    last_processed_at:         {}, # forward-only; final value approximates when the workflow finished
    scope_spreadsheets:        { ttl: 3600 }, # scope grant expiry epoch
    scope_sync:                { ttl: 3600 },
    threads_found:             { counter: true },
    threads_processed:         { counter: true },
    portals_found:             { counter: true },
    portals_appended:          { counter: true },
    threads_max_internal_date: {} # max Gmail internalDate (millis), forward-only
  }.freeze

  STORES.each do |name, opts|
    klass = opts[:counter] ? CounterStore : self
    define_singleton_method(name) do |redis: REDIS|
      klass.new(prefix: name.to_s, ttl: opts[:ttl], redis:)
    end
  end
end
