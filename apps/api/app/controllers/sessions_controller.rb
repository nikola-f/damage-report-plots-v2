# frozen_string_literal: true

class SessionsController < ApplicationController
  LOGIN_SCOPE        = "email profile"
  SPREADSHEETS_SCOPE = "email profile https://www.googleapis.com/auth/spreadsheets.readonly"
  SYNC_SCOPE         = "email profile https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/spreadsheets"

  # Redis keys to set (with access token TTL) when each scope is granted.
  # SYNC_SCOPE includes SPREADSHEETS_SCOPE capabilities via include_granted_scopes.
  SCOPE_REDIS_KEYS = {
    SPREADSHEETS_SCOPE => %w[scope_spreadsheets],
    SYNC_SCOPE         => %w[scope_spreadsheets scope_sync]
  }.freeze

  ACCESS_TOKEN_TTL = 3600 # seconds — matches Google OAuth access token lifetime

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
      # Scope upgrade: update token and store expiry epoch for each granted scope
      user_id = session[:user_id]

      return render json: { error: "Account mismatch during scope upgrade" }, status: :unauthorized if auth["uid"] != user_id
      return render json: { error: "Invalid scope" }, status: :unprocessable_entity unless SCOPE_REDIS_KEYS.key?(scope)

      expires_at = Time.now.to_i + ACCESS_TOKEN_TTL
      UserStore.access_token.store(user_id, auth["credentials"]["token"])
      SCOPE_REDIS_KEYS[scope].each do |key|
        REDIS.set("#{key}:#{user_id}", expires_at, ex: ACCESS_TOKEN_TTL)
      end
      redirect_to "/"
    else
      # Fresh login — reset session to prevent fixation
      reset_session
      user_info = {
        google_id: auth["uid"],
        email:     auth["info"]["email"],
        name:      auth["info"]["name"],
        picture:   auth["info"]["image"]
      }

      UserStore.access_token.store(user_info[:google_id], auth["credentials"]["token"])

      session[:user_id] = user_info[:google_id]
      session[:email]   = user_info[:email]
      session[:name]    = user_info[:name]
      session[:picture] = user_info[:picture]

      redirect_to "/"
    end
  rescue StandardError => e
    Rails.logger.error "OAuth callback error: #{e.class}: #{e.message}"
    render json: { error: "Authentication failed" }, status: :unprocessable_entity
  end

  def logout
    reset_session
    render json: { message: "Logged out successfully" }, status: :ok
  end

  def failure
    render json: { error: "Authentication failed" }, status: :unauthorized
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
