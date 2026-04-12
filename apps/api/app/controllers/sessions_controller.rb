# frozen_string_literal: true

class SessionsController < ApplicationController
  def google_oauth2
    # This endpoint redirects to Google OAuth
    # In an API-only app, clients should use POST to /auth/google_oauth2
    # which OmniAuth will handle
    head :ok
  end

  def google_callback
    auth = request.env["omniauth.auth"]

    return render json: { error: "Authentication failed" }, status: :unauthorized unless auth

    user_info = {
      google_id: auth["uid"],
      email:     auth["info"]["email"],
      name:      auth["info"]["name"],
      picture:   auth["info"]["image"]
    }

    AccessTokenStore.new.store(user_info[:google_id], auth["credentials"]["token"])

    session[:user_id] = user_info[:google_id]
    session[:email]   = user_info[:email]
    session[:name]    = user_info[:name]
    session[:picture] = user_info[:picture]

    render json: {
      user: {
        id:      user_info[:google_id],
        email:   user_info[:email],
        name:    user_info[:name],
        picture: user_info[:picture]
      }
    }, status: :ok
  rescue StandardError => e
    render json: { error: "Authentication failed", message: e.message }, status: :unprocessable_entity
  end

  def logout
    reset_session
    render json: { message: "Logged out successfully" }, status: :ok
  end

  def failure
    # OmniAuth failure callback
    render json: {
      error: "Authentication failed",
      message: params[:message],
      strategy: params[:strategy]
    }, status: :unauthorized
  end
end
