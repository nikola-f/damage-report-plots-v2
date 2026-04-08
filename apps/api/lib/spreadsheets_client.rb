# frozen_string_literal: true

require "net/http"
require "json"

class SpreadsheetsClient
  BASE_URL = "https://sheets.googleapis.com/v4"

  class ApiError < StandardError; end

  def initialize(access_token)
    @access_token = access_token
  end

  # @param title    [String]              スプレッドシートのタイトル
  # @param template [SpreadsheetTemplate] シート構成の定義
  # @return [String] 作成されたスプレッドシートの ID
  def create_spreadsheet(title:, template:)
    response = post("/spreadsheets", build_body(title:, template:))
    response["spreadsheetId"]
  end

  private

  def build_body(title:, template:)
    {
      properties: { title: },
      sheets:     template.sheets.map do |sheet|
        {
          properties: { title: sheet.name },
          data:       [{
            startRow:    0,
            startColumn: 0,
            rowData:     [{
              values: sheet.headers.map { |h| { userEnteredValue: { stringValue: h } } }
            }]
          }]
        }
      end
    }
  end

  def post(path, body)
    uri             = URI("#{BASE_URL}#{path}")
    request         = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@access_token}"
    request["Content-Type"]  = "application/json"
    request.body    = JSON.generate(body)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    raise ApiError, "Sheets API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
