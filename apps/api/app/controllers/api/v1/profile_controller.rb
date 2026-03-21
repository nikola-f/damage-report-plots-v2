# frozen_string_literal: true

module Api
  module V1
    class ProfileController < ApplicationController
      include Authenticatable

      def show
        # Example protected endpoint that requires JWT authentication
        render json: {
          message: 'Access granted to protected resource',
          user: current_user
        }, status: :ok
      end
    end
  end
end
