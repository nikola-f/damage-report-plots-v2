# frozen_string_literal: true

class SessionsController < ApplicationController
  LOGIN_SCOPE        = "email profile"
  SPREADSHEETS_SCOPE = "email profile https://www.googleapis.com/auth/spreadsheets.readonly"
  SYNC_SCOPE         = "email profile https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/spreadsheets"

  SCOPE_LEVEL = {
    LOGIN_SCOPE        => 1,
    SPREADSHEETS_SCOPE => 2,
    SYNC_SCOPE         => 3
  }.freeze

  def google_oauth2
    # This endpoint redirects to Google OAuth
    # In an API-only app, clients should use POST to /auth/google_oauth2
    # which OmniAuth will handle
    head :ok
  end

  def google_callback
    auth = request.env["omniauth.auth"]

    return render json: { error: "Authentication failed" }, status: :unauthorized unless auth

    if (scope = session.delete(:requested_scope))
      # Scope upgrade: update token and record the new scope level
      UserStore.access_token.store(session[:user_id], auth["credentials"]["token"])
      session[:scope_level] = SCOPE_LEVEL[scope]
      render json: { granted_scope: scope }, status: :ok
    else
      # Fresh login
      user_info = {
        google_id: auth["uid"],
        email:     auth["info"]["email"],
        name:      auth["info"]["name"],
        picture:   auth["info"]["image"]
      }

      UserStore.access_token.store(user_info[:google_id], auth["credentials"]["token"])

      session[:user_id]     = user_info[:google_id]
      session[:email]       = user_info[:email]
      session[:name]        = user_info[:name]
      session[:picture]     = user_info[:picture]
      session[:scope_level] = SCOPE_LEVEL[LOGIN_SCOPE]

      render json: {
        user: {
          id:      user_info[:google_id],
          email:   user_info[:email],
          name:    user_info[:name],
          picture: user_info[:picture]
        }
      }, status: :ok
    end
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

  def grant_spreadsheets
    return render json: { error: "Unauthorized" }, status: :unauthorized unless session[:user_id]

    session[:requested_scope] = SPREADSHEETS_SCOPE
    render json: { authorization_url: "/auth/google_oauth2" }, status: :ok
  end

  def grant_sync
    return render json: { error: "Unauthorized" }, status: :unauthorized unless session[:user_id]

    session[:requested_scope] = SYNC_SCOPE
    render json: { authorization_url: "/auth/google_oauth2" }, status: :ok
  end
end
