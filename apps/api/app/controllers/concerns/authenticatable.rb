# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request!
  end

  private

  def authenticate_request!
    header = request.headers["Authorization"]
    header = header.split.last if header

    begin
      @decoded_token = JsonWebToken.decode(header)
      @current_user_id = @decoded_token["sub"]
      @current_user_email = @decoded_token["email"]
      @current_user_name = @decoded_token["name"]
    rescue JWT::ExpiredSignature
      render json: { error: "Unauthorized - Token expired" }, status: :unauthorized
    rescue JWT::DecodeError
      render json: { error: "Unauthorized - Invalid token" }, status: :unauthorized
    end
  end

  def current_user_id
    @current_user_id
  end

  def current_user_email
    @current_user_email
  end

  def current_user_name
    @current_user_name
  end

  def current_user
    {
      id: @current_user_id,
      email: @current_user_email,
      name: @current_user_name
    }
  end
end
