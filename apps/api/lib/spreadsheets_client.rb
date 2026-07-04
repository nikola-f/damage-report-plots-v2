# frozen_string_literal: true

class SpreadsheetsClient < GoogleApiClient
  BASE_URL        = "https://sheets.googleapis.com/v4"
  API_NAME        = "Sheets"
  DEFINITION_PATH = Rails.root.join("config/spreadsheet_definition.json")
  PROTECTION_PATH = Rails.root.join("config/spreadsheet_protection.json")

  class ApiError < StandardError; end

  # @return [String] 作成されたスプレッドシートの ID
  def create_spreadsheet
    body = JSON.load_file(DEFINITION_PATH)
    response = post("/spreadsheets", body)
    response["spreadsheetId"]
  end

  # batchUpdate で保護範囲を設定する。
  # requests が空のときは何もしない。
  #
  # @param spreadsheet_id [String]
  def protect_ranges(spreadsheet_id:)
    body = JSON.load_file(PROTECTION_PATH)
    return if body["requests"].empty?

    post("/spreadsheets/#{encode(spreadsheet_id)}:batchUpdate", body)
  end

  # スプレッドシートのメタデータを取得する。
  # 存在しない場合は ApiError (404) を送出する。
  #
  # @param spreadsheet_id [String]
  # @return [Hash]
  def get_spreadsheet(spreadsheet_id:)
    get("/spreadsheets/#{encode(spreadsheet_id)}")
  end

  # 指定範囲の値を取得する。UNFORMATTED_VALUE で数値を数値のまま返す。
  #
  # @param spreadsheet_id       [String] 対象スプレッドシートの ID
  # @param range                [String] A1 記法 or 名前付き範囲名 (e.g. "plotsExport")
  # @param value_render_option  [String]
  # @return [Array<Array>] 値の二次元配列 (空なら [])
  def get_values(spreadsheet_id:, range:, value_render_option: "UNFORMATTED_VALUE")
    response = get(
      "/spreadsheets/#{encode(spreadsheet_id)}/values/#{encode(range)}",
      query: { valueRenderOption: value_render_option }
    )
    response["values"] || []
  end

  # 既存シートの末尾に行データをバッチ追加する。
  #
  # @param spreadsheet_id [String]       対象スプレッドシートの ID
  # @param sheet_name     [String]       書き込み先シート名 (e.g. "reports")
  # @param rows           [Array<Array>] 追加する行データ
  def append_rows(spreadsheet_id:, sheet_name:, rows:)
    range = "#{sheet_name}!A1"
    post(
      "/spreadsheets/#{encode(spreadsheet_id)}/values/#{encode(range)}:append",
      { values: rows },
      query: { valueInputOption: "RAW" }
    )
  end
end
