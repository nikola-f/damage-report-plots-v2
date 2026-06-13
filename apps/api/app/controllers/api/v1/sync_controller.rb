# frozen_string_literal: true

module Api
  module V1
    class SyncController < ApplicationController
      include Authenticatable

      def create
        ensure_spreadsheet_exists
        GmailThreadListWorker.perform_async(current_user_id, after_epoch)
        UserStore.last_synced_at.store(current_user_id, Time.now.to_i.to_s)
        UserStore.threads_found.store(current_user_id, "0")
        UserStore.threads_processed.store(current_user_id, "0")
        UserStore.portals_found.store(current_user_id, "0")
        UserStore.portals_appended.store(current_user_id, "0")
        head :accepted
      end

      # Clears the sync resume point so the next sync starts from the beginning.
      def reset
        UserStore.threads_max_internal_date.delete(current_user_id)
        head :no_content
      end

      private

      # Resume from the latest processed thread. threads_max_internal_date is the
      # Gmail internalDate in milliseconds; convert to a Unix epoch in seconds.
      # Returns nil on first sync so the worker falls back to DEFAULT_AFTER_DATE.
      def after_epoch
        UserStore.threads_max_internal_date.fetch(current_user_id).to_i / 1000
      rescue KeyError
        nil
      end

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
