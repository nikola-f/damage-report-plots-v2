# frozen_string_literal: true

class ApplicationController < ActionController::API
  rescue_from JWT::DecodeError, with: :unauthorized_response
  rescue_from JWT::ExpiredSignature, with: :token_expired_response

  private

  def unauthorized_response
    render json: { error: "Unauthorized - Invalid token" }, status: :unauthorized
  end

  def token_expired_response
    render json: { error: "Unauthorized - Token expired" }, status: :unauthorized
  end
end
