# frozen_string_literal: true

# Stores Google Spreadsheet IDs in Redis keyed by user_id (Google account ID).
# Persists across login sessions so users can access their spreadsheet after
# the access token expires.
#
# @example Storing a spreadsheet ID after creation
#   SpreadsheetIdStore.new.store(user_id, spreadsheet_id)
#
# @example Retrieving the spreadsheet ID inside a job
#   spreadsheet_id = SpreadsheetIdStore.new.fetch(user_id)
class SpreadsheetIdStore
  KEY_PREFIX   = "spreadsheet_id"
  USER_ID_ATTR = "user_id" # SQS message attribute name for passing user IDs between workers

  def initialize(redis: REDIS)
    @redis = redis
  end

  # @param user_id        [String] Google account ID
  # @param spreadsheet_id [String]
  def store(user_id, spreadsheet_id)
    @redis.set(redis_key(user_id), spreadsheet_id)
  end

  # @param user_id [String] Google account ID
  # @return [String] spreadsheet ID
  # @raise [KeyError] if not found
  def fetch(user_id)
    id = @redis.get(redis_key(user_id))
    raise KeyError, "Spreadsheet ID not found: #{user_id}" unless id

    id
  end

  private

  def redis_key(key) = "#{KEY_PREFIX}:#{key}"
end
