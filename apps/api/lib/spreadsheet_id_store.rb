# frozen_string_literal: true

# Stores Google Spreadsheet IDs in Redis keyed by token_key.
# Allows SpreadsheetSyncWorker to look up the target spreadsheet for each user.
#
# @example Storing a spreadsheet ID after creation
#   SpreadsheetIdStore.new.store(token_key, spreadsheet_id)
#
# @example Retrieving the spreadsheet ID inside a job
#   spreadsheet_id = SpreadsheetIdStore.new.fetch(token_key)
class SpreadsheetIdStore
  TTL        = 14 * 24 * 60 * 60 # 14 days in seconds
  KEY_PREFIX = "spreadsheet_id"

  def initialize(redis: REDIS)
    @redis = redis
  end

  # @param token_key      [String] UUID key from AccessTokenStore
  # @param spreadsheet_id [String]
  def store(token_key, spreadsheet_id)
    @redis.set(redis_key(token_key), spreadsheet_id, ex: TTL)
  end

  # @param token_key [String]
  # @return [String] spreadsheet ID
  # @raise [KeyError] if not found
  def fetch(token_key)
    id = @redis.get(redis_key(token_key))
    raise KeyError, "Spreadsheet ID not found: #{token_key}" unless id

    id
  end

  private

  def redis_key(key) = "#{KEY_PREFIX}:#{key}"
end
