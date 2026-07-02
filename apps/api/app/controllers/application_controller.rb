# frozen_string_literal: true

class ApplicationController < ActionController::API
  # CORS allowed origins double as the legitimate browser origins for
  # state-changing requests (the SPA and API share an origin via CloudFront).
  ALLOWED_ORIGINS = Settings.allowed_origins.split(",").freeze

  before_action :verify_origin!

  private

  # CSRF defense in depth alongside the SameSite=Lax session cookie: reject
  # state-changing requests whose Origin header is not an allowed origin.
  # Requests without an Origin header (non-browser clients) pass — they do
  # not carry ambient cookies, so CSRF does not apply to them.
  def verify_origin!
    return if request.get? || request.head?

    origin = request.origin
    return if origin.nil? || ALLOWED_ORIGINS.include?(origin)

    render json: { error: "Forbidden" }, status: :forbidden
  end
end
