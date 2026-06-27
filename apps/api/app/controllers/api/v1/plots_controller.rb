# frozen_string_literal: true

module Api
  module V1
    class PlotsController < ApplicationController
      include Authenticatable

      # 列指定 A1 記法。名前付き範囲は作成時の行数 (デフォルト 1000) で固定され
      # スピルで増えた行に追従しないため、グリッドの実サイズを追う A:F を使う。
      RANGE = "plots!A:F"

      def show
        spreadsheet_id = UserStore.spreadsheet_id.fetch(current_user_id)
        access_token   = UserStore.access_token.fetch(current_user_id)

        rows = SpreadsheetsClient.new(access_token).get_values(
          spreadsheet_id:, range: RANGE
        )
        render json: rows.filter_map { |row| to_plot(row) }, status: :ok
      rescue KeyError, SpreadsheetsClient::ApiError
        # spreadsheet 未作成 / トークン失効・未取得 / 名前付き範囲未定義 のいずれも
        # 再認可フロー (grant/spreadsheets) へ誘導する。
        render json: { error: "reauthorization_required" }, status: :unauthorized
      end

      private

      def to_plot(row)
        return nil if row.compact.empty? # 末尾の空行を除外

        plot = {
          lat:    row[0],
          lng:    row[1],
          owned:  row[2],
          count:  row[3],
          latest: row[4]
        }
        # 件数==1 のとき oldest は空。その場合はキー自体を含めない。
        oldest = row[5]
        plot[:oldest] = oldest unless oldest.nil? || oldest == ""
        plot
      end
    end
  end
end
