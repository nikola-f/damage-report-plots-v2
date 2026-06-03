# frozen_string_literal: true

module Api
  module V1
    class StatusController < ApplicationController
      include Authenticatable
      include UserStatusData
      include ApplicationStatusData

      def show
        render json: {
          user: user_status,
          app:  application_status
        }, status: :ok
      end
    end
  end
end
