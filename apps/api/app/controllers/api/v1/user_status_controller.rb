# frozen_string_literal: true

module Api
  module V1
    class UserStatusController < ApplicationController
      include Authenticatable

      def show
        render json: {
          spreadsheet_exists: spreadsheet_exists?,
          last_synced_at:     last_synced_at,
          scope_expires_at:   {
            spreadsheets: REDIS.get("scope_spreadsheets:#{current_user_id}")&.to_i,
            sync:         REDIS.get("scope_sync:#{current_user_id}")&.to_i
          }
        }, status: :ok
      end

      private

      def spreadsheet_exists?
        UserStore.spreadsheet_id.fetch(current_user_id)
        true
      rescue KeyError
        false
      end

      def last_synced_at
        UserStore.last_synced_at.fetch(current_user_id).to_i
      rescue KeyError
        nil
      end
    end
  end
end
