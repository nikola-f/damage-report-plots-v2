# frozen_string_literal: true

module Api
  module V1
    class SyncController < ApplicationController
      include Authenticatable

      def create
        ensure_spreadsheet_exists
        GmailThreadListWorker.perform_async(current_user_id, params[:after_date])
        REDIS.set("sync_queued_at:#{current_user_id}", Time.now.utc.iso8601)
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
