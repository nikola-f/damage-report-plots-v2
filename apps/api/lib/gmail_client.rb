require "net/http"
require "json"

class GmailClient
  BASE_URL = "https://gmail.googleapis.com/gmail/v1"
  BATCH_BASE_URL = "https://www.googleapis.com"
  BATCH_BOUNDARY = "batch_boundary_gmail_v1"

  PER_PROJECT_LIMIT = 1_200_000  # quota units per minute
  PER_USER_LIMIT    = 15_000     # quota units per minute per user
  QUOTA_WINDOW      = 60         # seconds

  QUOTA_UNITS = {
    list_threads:             10,
    get_thread:               10,
    batch_get_threads_per_id: 10
  }.freeze

  def initialize(access_token, user_id: nil, redis: nil)
    @access_token = access_token
    @user_id = user_id
    @redis = redis
  end

  # Calls users.threads.list API and returns the parsed response.
  # https://developers.google.com/gmail/api/reference/rest/v1/users.threads/list
  #
  # @param q [String, nil] Gmail search query (same format as Gmail search box)
  # @param page_token [String, nil] Page token from a previous response to retrieve the next page
  # @return [Hash] Parsed JSON response containing :threads, :nextPageToken, :resultSizeEstimate
  def list_threads(q: nil, page_token: nil)
    consume_quota(QUOTA_UNITS[:list_threads])

    params = {
      q: q,
      pageToken: page_token
    }.compact

    get("/users/me/threads", params)
  end

  # Calls users.threads.get API and returns the parsed response.
  # https://developers.google.com/gmail/api/reference/rest/v1/users.threads/get
  #
  # @param id [String] The ID of the thread to retrieve
  # @return [Hash] Parsed JSON response containing the thread with its messages
  def get_thread(id)
    consume_quota(QUOTA_UNITS[:get_thread])
    get("/users/me/threads/#{id}")
  end

  # Calls users.threads.get for multiple IDs in a single request using the Gmail Batch API.
  # https://developers.google.com/gmail/api/guides/batch
  #
  # @param ids [Array<String>] Thread IDs to retrieve
  # @return [Array<Hash>] Parsed thread hashes in the same order as ids
  def batch_get_threads(ids)
    return [] if ids.empty?

    consume_quota(QUOTA_UNITS[:batch_get_threads_per_id] * ids.size)

    response = batch_post(ids)
    parse_batch_response(response, ids)
  end

  class ApiError < StandardError; end
  class QuotaExceededError < StandardError; end

  private

  def consume_quota(units)
    return unless @redis

    [
      ["gmail_quota:project", PER_PROJECT_LIMIT],
      ["gmail_quota:user:#{@user_id}", PER_USER_LIMIT]
    ].each do |key, limit|
      new_count = @redis.incrby(key, units)
      @redis.expire(key, QUOTA_WINDOW) if new_count == units
      raise QuotaExceededError, "Gmail API quota exceeded: #{key}" if new_count > limit
    end
  end

  def get(path, params = {})
    base_uri = URI("#{BASE_URL}#{path}")

    query_string = build_query_string(params)
    request_path = query_string.empty? ? base_uri.path : "#{base_uri.path}?#{query_string}"

    request = Net::HTTP::Get.new(request_path)
    request["Authorization"] = "Bearer #{@access_token}"

    response = Net::HTTP.start(base_uri.hostname, base_uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "Gmail API error: #{response.code} #{response.body}"
    end

    JSON.parse(response.body)
  end

  def build_query_string(params)
    params.flat_map do |key, value|
      Array(value).map { |v| "#{URI.encode_www_form_component(key.to_s)}=#{URI.encode_www_form_component(v.to_s)}" }
    end.join("&")
  end

  def batch_post(ids)
    base_uri = URI(BATCH_BASE_URL)
    body = build_batch_body(ids)

    request = Net::HTTP::Post.new("/batch/gmail/v1")
    request["Authorization"] = "Bearer #{@access_token}"
    request["Content-Type"] = "multipart/mixed; boundary=#{BATCH_BOUNDARY}"
    request.body = body

    response = Net::HTTP.start(base_uri.hostname, base_uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "Gmail API error: #{response.code} #{response.body}"
    end

    response
  end

  def build_batch_body(ids)
    parts = ids.each_with_index.map do |id, index|
      "--#{BATCH_BOUNDARY}\r\n" \
      "Content-Type: application/http\r\n" \
      "Content-ID: <#{index}>\r\n" \
      "\r\n" \
      "GET /gmail/v1/users/me/threads/#{id}\r\n" \
      "Authorization: Bearer #{@access_token}\r\n" \
      "\r\n"
    end

    parts.join + "--#{BATCH_BOUNDARY}--\r\n"
  end

  def parse_batch_response(response, ids)
    boundary = response["Content-Type"][/boundary=([^\s;]+)/, 1]
    results = Array.new(ids.size)

    raw_parts = response.body.split("--#{boundary}")
    # drop preamble (first element) and closing delimiter (last element "--\r\n")
    raw_parts = raw_parts[1..-2]

    raw_parts.each do |part|
      index, thread = parse_batch_part(part)
      results[index] = thread
    end

    results
  end

  def parse_batch_part(part)
    # Split outer MIME headers from inner HTTP response on first blank line
    mime_headers_section, http_response = part.split(/\r?\n\r?\n/, 2)

    index = mime_headers_section[/Content-ID:\s*response-(\d+)/i, 1].to_i

    # Split HTTP status line + headers from JSON body on first blank line
    http_head, json_body = http_response.split(/\r?\n\r?\n/, 2)

    status_code = http_head.lines.first.to_s.split[1].to_i

    unless (200..299).cover?(status_code)
      raise ApiError, "Gmail API error: #{status_code} (batch part #{index})"
    end

    [index, JSON.parse(json_body.strip)]
  end
end
