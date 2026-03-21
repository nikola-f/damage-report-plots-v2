class SessionsController < ApplicationController
  def google_oauth2
    # This endpoint redirects to Google OAuth
    # In an API-only app, clients should use POST to /auth/google_oauth2
    # which OmniAuth will handle
    head :ok
  end

  def google_callback
    # Get OAuth data from OmniAuth
    auth = request.env['omniauth.auth']

    unless auth
      return render json: { error: 'Authentication failed' }, status: :unauthorized
    end

    # Extract user info from Google
    user_info = {
      google_id: auth['uid'],
      email: auth['info']['email'],
      name: auth['info']['name'],
      picture: auth['info']['image']
    }

    # Create JWT access token (15 minutes)
    access_token = JsonWebToken.encode({
      sub: user_info[:google_id],
      email: user_info[:email],
      name: user_info[:name],
      picture: user_info[:picture]
    })

    # Return tokens and user info
    render json: {
      access_token: access_token,
      token_type: 'Bearer',
      expires_in: 900, # 15 minutes in seconds
      user: {
        id: user_info[:google_id],
        email: user_info[:email],
        name: user_info[:name],
        picture: user_info[:picture]
      },
      google_tokens: {
        access_token: auth['credentials']['token'],
        refresh_token: auth['credentials']['refresh_token'],
        expires_at: auth['credentials']['expires_at']
      }
    }, status: :ok
  rescue => e
    render json: { error: 'Authentication failed', message: e.message }, status: :unprocessable_entity
  end

  def logout
    # Since JWT is stateless, just return success
    # Client should delete tokens
    render json: { message: 'Logged out successfully' }, status: :ok
  end

  def failure
    # OmniAuth failure callback
    render json: {
      error: 'Authentication failed',
      message: params[:message],
      strategy: params[:strategy]
    }, status: :unauthorized
  end
end
