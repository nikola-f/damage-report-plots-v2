# frozen_string_literal: true

class ApplicationController < ActionController::API
  before_action :set_security_headers

  private

  def set_security_headers
    response.headers["X-Content-Type-Options"] = "nosniff"
  end
end
