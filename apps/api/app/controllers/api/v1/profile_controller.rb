# frozen_string_literal: true

module Api
  module V1
    class ProfileController < ApplicationController
      include Authenticatable

      def show
        render json: current_user, status: :ok
      end
    end
  end
end
