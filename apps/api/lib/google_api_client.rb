# frozen_string_literal: true

require "net/http"
require "json"
require "erb"

# Shared HTTP layer for Google REST APIs: Bearer auth, TLS, JSON, and error
# mapping. Subclasses define BASE_URL, API_NAME and an ApiError class.
#
# Error messages carry only the HTTP status and Google's error.message —
# never the raw response body, which can contain user data (mail snippets,
# sheet contents) and would end up in logs via the exception message.
class GoogleApiClient
  def initialize(access_token)
    @access_token = access_token
  end

  private

  def get(path, query: {})
    uri     = build_uri(path, query)
    request = Net::HTTP::Get.new(uri)
    perform_json(uri, request)
  end

  def post(path, body, query: {})
    uri     = build_uri(path, query)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
    perform_json(uri, request)
  end

  # Percent-encodes one path segment (also encodes "/", "!", ":", etc.) so
  # values interpolated into a path cannot alter the request target.
  def encode(segment)
    ERB::Util.url_encode(segment.to_s)
  end

  def build_uri(path, query)
    uri       = URI("#{self.class::BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) unless query.empty?
    uri
  end

  # Executes the request and raises the subclass ApiError (with a sanitized
  # message) on a non-2xx response. Returns the raw Net::HTTPResponse for
  # callers with non-JSON payloads (e.g. Gmail batch multipart).
  def execute(uri, request)
    request["Authorization"] = "Bearer #{@access_token}"
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    raise self.class::ApiError, error_message(response) unless response.is_a?(Net::HTTPSuccess)

    response
  end

  def perform_json(uri, request)
    body = execute(uri, request).body
    return {} if body.nil? || body.strip.empty?

    JSON.parse(body)
  end

  # e.g. "Sheets API error: 403 The caller does not have permission"
  def error_message(response)
    detail = begin
      JSON.parse(response.body).dig("error", "message")
    rescue JSON::ParserError, TypeError
      nil
    end
    ["#{self.class::API_NAME} API error:", response.code, detail].compact.join(" ")
  end
end
