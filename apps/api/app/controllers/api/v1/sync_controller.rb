# frozen_string_literal: true

module Api
  module V1
    class SyncController < ApplicationController
      include Authenticatable

      def create
        # Throttle repeated syncs: reject if the previous run started less than
        # Settings.sync_min_interval seconds ago. Cheapest guard, so check first.
        if (wait = retry_after_seconds)
          response.headers["Retry-After"] = wait.to_s
          return render json: { error: "rate_limited", retry_after: wait }, status: :too_many_requests
        end

        # The Google access token (Redis TTL 3600s) can be evicted between login
        # and sync. Without it the worker fails with KeyError and dead-jobs, so
        # reject early and signal the client to re-acquire the sync scope.
        return render json: { error: "reauthorization_required" }, status: :unauthorized unless access_token_present?

        ensure_spreadsheet_exists
        GmailThreadListWorker.perform_async(current_user_id, after_epoch)
        UserStore.last_synced_at.store(current_user_id, Time.now.to_i.to_s)
        UserStore::COUNTER_STORE_NAMES.each do |name|
          UserStore.public_send(name).store(current_user_id, "0")
        end
        head :accepted
      end

      # Clears the sync resume point so the next sync starts from the beginning,
      # and drops the stored spreadsheet ID so the next sync recreates the
      # spreadsheet (via ensure_spreadsheet_exists).
      def reset
        UserStore.threads_max_internal_date.delete(current_user_id)
        UserStore.spreadsheet_id.delete(current_user_id)
        head :no_content
      end

      private

      # Seconds the client must wait before syncing again, or nil if a sync is
      # allowed now (no prior sync recorded, or the interval has elapsed).
      def retry_after_seconds
        last_synced_at = UserStore.last_synced_at.fetch_or_nil(current_user_id)
        return nil unless last_synced_at

        remaining = Settings.sync_min_interval - (Time.now.to_i - last_synced_at.to_i)
        remaining.positive? ? remaining : nil
      end

      def access_token_present?
        !UserStore.access_token.fetch_or_nil(current_user_id).nil?
      end

      # Resume from the latest processed thread. threads_max_internal_date is the
      # Gmail internalDate in milliseconds; convert to a Unix epoch in seconds.
      # Returns nil on first sync so the worker falls back to DEFAULT_AFTER_DATE.
      def after_epoch
        max_internal_date = UserStore.threads_max_internal_date.fetch_or_nil(current_user_id)
        max_internal_date && max_internal_date.to_i / 1000
      end

      def ensure_spreadsheet_exists
        return if UserStore.spreadsheet_id.fetch_or_nil(current_user_id)

        access_token   = UserStore.access_token.fetch(current_user_id)
        client         = SpreadsheetsClient.new(access_token)
        spreadsheet_id = client.create_spreadsheet
        client.protect_ranges(spreadsheet_id:)
        UserStore.spreadsheet_id.store(current_user_id, spreadsheet_id)
      end
    end
  end
end
