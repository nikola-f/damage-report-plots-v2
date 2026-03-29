require "net/http"
require "json"

class GmailClient
  BASE_URL = "https://gmail.googleapis.com/gmail/v1"

  def initialize(access_token)
    @access_token = access_token
  end

  # Calls users.threads.list API and returns the parsed response.
  # https://developers.google.com/gmail/api/reference/rest/v1/users.threads/list
  #
  # @param q [String, nil] Gmail search query (same format as Gmail search box)
  # @param page_token [String, nil] Page token from a previous response to retrieve the next page
  # @return [Hash] Parsed JSON response containing :threads, :nextPageToken, :resultSizeEstimate
  def list_threads(q: nil, page_token: nil)
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
    get("/users/me/threads/#{id}")
  end

  class ApiError < StandardError; end

  private

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
end
