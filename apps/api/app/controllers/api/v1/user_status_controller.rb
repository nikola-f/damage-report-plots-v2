# frozen_string_literal: true

module Api
  module V1
    class UserStatusController < ApplicationController
      include Authenticatable

      def show
        render json: {
          spreadsheet_exists: spreadsheet_exists?,
          scope_level:        session[:scope_level],
          sync_queued_at:     REDIS.get("sync_queued_at:#{current_user_id}")
        }, status: :ok
      end

      private

      def spreadsheet_exists?
        UserStore.spreadsheet_id.fetch(current_user_id)
        true
      rescue KeyError
        false
      end
    end
  end
end
