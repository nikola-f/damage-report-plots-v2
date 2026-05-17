# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request!
  end

  private

  def authenticate_request!
    render json: { error: "Unauthorized" }, status: :unauthorized unless session[:user_id]
  end

  def current_user_id
    session[:user_id]
  end

  def current_user_email
    session[:email]
  end

  def current_user_name
    session[:name]
  end

  def current_user
    {
      id:      session[:user_id],
      email:   session[:email],
      name:    session[:name],
      picture: session[:picture]
    }
  end
end
