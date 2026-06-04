# frozen_string_literal: true

# Fetches full Gmail thread data for the given thread IDs using the Batch API.
#
# Designed to be called from a Sidekiq Worker.
# Automatically chunks IDs to respect the Gmail Batch API limit (100 per request).
#
# @example
#   threads = GmailThreadBatchFetcher.new(
#     access_token: token
#   ).call(["id1", "id2", "id3"])
class GmailThreadBatchFetcher
  BATCH_SIZE        = 20
  INTER_BATCH_SLEEP = 1   # seconds; throttles QPM consumption between batch API calls
  MAX_BACKOFF       = 32  # seconds; exponential backoff cap for Gmail 429 errors
  MAX_RETRIES       = 6   # 1+2+4+8+16+32 = 63s total wait, covering one quota window

  def initialize(access_token:, gmail_client: nil)
    @gmail_client = gmail_client || GmailClient.new(access_token, redis: REDIS)
  end

  # @param thread_ids [Array<String>]
  # @yield [GmailMessage] each message in streaming mode (limits peak memory to one batch at a time)
  # @return [Array<GmailMessage>, nil] array when no block given; nil when block given
  def call(thread_ids, &block)
    return (block ? nil : []) if thread_ids.empty?

    if block
      each_batch(thread_ids) { |messages| messages.each(&block) }
      nil
    else
      [].tap { |result| each_batch(thread_ids) { |messages| result.concat(messages) } }
    end
  end

  private

  def each_batch(thread_ids)
    thread_ids.each_slice(BATCH_SIZE).with_index(1) do |batch, i|
      sleep INTER_BATCH_SLEEP if i > 1
      yield fetch_with_retry(batch)
    end
  end

  def fetch_with_retry(batch, attempt: 0)
    raw_threads = @gmail_client.batch_get_threads(batch)
    raw_threads.flat_map do |raw|
      next [] if raw.nil?
      (raw["messages"] || []).map { |m| GmailMessage.new(m) }
    end
  rescue GmailClient::ApiError => e
    raise unless e.message.match?(/429|503|Rate Limit Exceeded|Quota exceeded|Too many concurrent|unavailable/i)
    raise if attempt >= MAX_RETRIES
    wait = [2**attempt, MAX_BACKOFF].min
    Rails.logger.warn "GmailThreadBatchFetcher retry attempt=#{attempt + 1}/#{MAX_RETRIES} sleep=#{wait}s reason=#{e.message}"
    sleep wait
    fetch_with_retry(batch, attempt: attempt + 1)
  end
end
