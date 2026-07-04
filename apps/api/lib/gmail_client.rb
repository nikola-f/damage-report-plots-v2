# frozen_string_literal: true

class GmailClient < GoogleApiClient
  BASE_URL       = "https://gmail.googleapis.com/gmail/v1"
  API_NAME       = "Gmail"
  BATCH_BASE_URL = "https://www.googleapis.com"
  BATCH_BOUNDARY = "batch_boundary_gmail_v1"

  # Fields to retrieve for each thread via users.threads.get.
  # Limits the response payload to only what downstream processing needs.
  THREAD_FIELDS = "messages/id,messages/internalDate,messages/payload/parts/mimeType,messages/payload/parts/body/data"

  class ApiError < StandardError; end

  # Calls users.threads.list API and returns the parsed response.
  # https://developers.google.com/gmail/api/reference/rest/v1/users.threads/list
  #
  # @param q [String, nil] Gmail search query (same format as Gmail search box)
  # @param page_token [String, nil] Page token from a previous response to retrieve the next page
  # @return [Hash] Parsed JSON response containing :threads, :nextPageToken, :resultSizeEstimate
  def list_threads(q: nil, page_token: nil)
    params = {
      q: q,
      pageToken: page_token,
      fields: "threads/id,nextPageToken"
    }.compact

    get("/users/me/threads", query: params)
  end

  # Calls users.threads.get for multiple IDs in a single request using the Gmail Batch API.
  # https://developers.google.com/gmail/api/guides/batch
  #
  # @param ids [Array<String>] Thread IDs to retrieve
  # @return [Array<Hash>] Parsed thread hashes in the same order as ids
  def batch_get_threads(ids)
    return [] if ids.empty?

    response = batch_post(ids)
    parse_batch_response(response, ids)
  end

  private

  def batch_post(ids)
    uri     = URI("#{BATCH_BASE_URL}/batch/gmail/v1")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "multipart/mixed; boundary=#{BATCH_BOUNDARY}"
    request.body = build_batch_body(ids)

    execute(uri, request)
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

    index = mime_headers_section[/Content-ID:\s*<?response-(\d+)>?/i, 1].to_i

    # Split HTTP status line + headers from JSON body on first blank line
    http_head, json_body = http_response.split(/\r?\n\r?\n/, 2)

    status_code = http_head.lines.first.to_s.split[1].to_i

    unless (200..299).cover?(status_code)
      error_message = JSON.parse(json_body.strip).dig("error", "message") rescue nil
      detail = [status_code.to_s, error_message, "(batch part #{index})"].compact.join(" ")
      raise ApiError, "Gmail API error: #{detail}"
    end

    [index, JSON.parse(json_body.strip)]
  end
end
