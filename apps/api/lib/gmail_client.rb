# frozen_string_literal: true

require "net/http"
require "json"
require "digest"

class GmailClient
  BASE_URL = "https://gmail.googleapis.com/gmail/v1"
  BATCH_BASE_URL = "https://www.googleapis.com"
  BATCH_BOUNDARY = "batch_boundary_gmail_v1"

  # Fields to retrieve for each thread via users.threads.get.
  # Limits the response payload to only what downstream processing needs.
  THREAD_FIELDS = "messages/id,messages/internalDate,messages/payload/parts/mimeType,messages/payload/parts/body/data"

  PER_PROJECT_LIMIT = 1_200_000  # quota units per minute
  PER_USER_LIMIT    = 15_000     # quota units per minute per user (Gmail API limit: 250 units/sec)
  QUOTA_WINDOW      = 60         # seconds

  QUOTA_UNITS = {
    list_threads: 10,
    batch_get_threads_per_id: 40
  }.freeze

  def initialize(access_token, redis: nil)
    @access_token = access_token
    @token_hash   = Digest::SHA256.hexdigest(access_token)
    @redis        = redis
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
      pageToken: page_token,
      fields: "threads/id,nextPageToken"
    }.compact

    get("/users/me/threads", params)
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
      ["gmail_quota:user:#{@token_hash}", PER_USER_LIMIT]
    ].each do |key, limit|
      new_count = @redis.incrby(key, units)
      @redis.expire(key, QUOTA_WINDOW) if new_count == units
      if new_count > limit
        @redis.decrby(key, units)
        raise QuotaExceededError, "Gmail API quota exceeded: #{key}"
      end
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

    raise ApiError, "Gmail API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    body = response.body
    return {} if body.nil? || body.strip.empty?

    JSON.parse(body)
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

    raise ApiError, "Gmail API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response
  end

  def build_batch_body(ids)
    parts = ids.each_with_index.map do |id, index|
      "--#{BATCH_BOUNDARY}\r\n" \
        "Content-Type: application/http\r\n" \
        "Content-ID: <#{index}>\r\n" \
        "\r\n" \
        "GET /gmail/v1/users/me/threads/#{id}?fields=#{THREAD_FIELDS}\r\n" \
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

    raise ApiError, "Gmail API error: #{status_code} (batch part #{index})" unless (200..299).cover?(status_code)

    [index, JSON.parse(json_body.strip)]
  end
end
