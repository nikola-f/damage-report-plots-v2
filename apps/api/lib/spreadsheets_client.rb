# frozen_string_literal: true

require "net/http"
require "json"

class SpreadsheetsClient
  BASE_URL        = "https://sheets.googleapis.com/v4"
  DEFINITION_PATH = Rails.root.join("config/spreadsheet_definition.json")

  class ApiError < StandardError; end

  def initialize(access_token)
    @access_token = access_token
  end

  # @param title [String] スプレッドシートのタイトル
  # @return [String] 作成されたスプレッドシートの ID
  def create_spreadsheet(title:)
    template = load_template
    response = post("/spreadsheets", build_body(title:, template:))
    response["spreadsheetId"]
  end

  # 既存シートの末尾に行データをバッチ追加する。
  #
  # @param spreadsheet_id [String]       対象スプレッドシートの ID
  # @param sheet_name     [String]       書き込み先シート名 (e.g. "Attacks")
  # @param rows           [Array<Array>] 追加する行データ
  def append_rows(spreadsheet_id:, sheet_name:, rows:)
    range = "#{sheet_name}!A1"
    post(
      "/spreadsheets/#{spreadsheet_id}/values/#{range}:append",
      { values: rows },
      query: { valueInputOption: "RAW" }
    )
  end

  private

  def load_template
    definition = JSON.load_file(DEFINITION_PATH)
    sheets = definition["sheets"].map do |s|
      SpreadsheetTemplate::Sheet.new(name: s["name"], headers: s["headers"])
    end
    SpreadsheetTemplate.new(sheets:)
  end

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

  def post(path, body, query: {})
    uri       = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) unless query.empty?
    request   = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@access_token}"
    request["Content-Type"]  = "application/json"
    request.body = JSON.generate(body)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    raise ApiError, "Sheets API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
