# frozen_string_literal: true

module Api
  module V1
    class SyncController < ApplicationController
      include Authenticatable

      def create
        if params[:after_date].present?
          begin
            Date.iso8601(params[:after_date])
          rescue Date::Error, ArgumentError
            return render json: { error: "Invalid after_date" }, status: :unprocessable_entity
          end
        end
        ensure_spreadsheet_exists
        GmailThreadListWorker.perform_async(current_user_id, params[:after_date])
        UserStore.last_synced_at.store(current_user_id, Time.now.to_i.to_s)
        head :accepted
      end

      private

      def ensure_spreadsheet_exists
        UserStore.spreadsheet_id.fetch(current_user_id)
      rescue KeyError
        access_token   = UserStore.access_token.fetch(current_user_id)
        client         = SpreadsheetsClient.new(access_token)
        spreadsheet_id = client.create_spreadsheet
        client.protect_ranges(spreadsheet_id:)
        UserStore.spreadsheet_id.store(current_user_id, spreadsheet_id)
      end
    end
  end
end
