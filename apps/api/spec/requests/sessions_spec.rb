# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sessions', type: :request do
  before do
    mock_jwt_credentials
  end

  describe 'GET /auth/google_oauth2/callback' do
    context 'with successful OAuth authentication' do
      before do
        mock_google_oauth_success
      end

      it 'returns JWT tokens and user information' do
        get '/auth/google_oauth2/callback'

        expect(response).to have_http_status(:ok)

        # Verify JWT token is present
        expect(json_response['access_token']).to be_present
        expect(json_response['token_type']).to eq('Bearer')
        expect(json_response['expires_in']).to eq(900)
      end

      it 'returns correct user information from Google' do
        get '/auth/google_oauth2/callback'

        expect(response).to have_http_status(:ok)

        user = json_response['user']
        expect(user['id']).to eq(test_user_id)
        expect(user['email']).to eq(test_user_email)
        expect(user['name']).to eq(test_user_name)
        expect(user['picture']).to eq(test_user_picture)
      end

      it 'returns Google OAuth tokens for API access' do
        get '/auth/google_oauth2/callback'

        expect(response).to have_http_status(:ok)

        google_tokens = json_response['google_tokens']
        expect(google_tokens['access_token']).to eq('google_access_token_123')
        expect(google_tokens['refresh_token']).to eq('google_refresh_token_456')
        expect(google_tokens['expires_at']).to be_present
      end

      it 'returns a valid decodable access token' do
        get '/auth/google_oauth2/callback'

        access_token = json_response['access_token']
        decoded = JsonWebToken.decode(access_token)

        expect(decoded['sub']).to eq(test_user_id)
        expect(decoded['email']).to eq(test_user_email)
        expect(decoded['name']).to eq(test_user_name)
        expect(decoded['iss']).to eq('damage-report-api')
      end
    end

    context 'with custom user data from Google' do
      before do
        mock_google_oauth_success(
          uid: 'custom_id_789',
          email: 'custom@example.com',
          name: 'Custom User'
        )
      end

      it 'uses the custom user data in tokens and response' do
        get '/auth/google_oauth2/callback'

        expect(json_response['user']['id']).to eq('custom_id_789')
        expect(json_response['user']['email']).to eq('custom@example.com')
        expect(json_response['user']['name']).to eq('Custom User')
      end
    end

    context 'with missing OAuth data' do
      before do
        # Clear any previously set mock auth to simulate missing data
        OmniAuth.config.mock_auth[:google_oauth2] = nil
      end

      it 'returns error when auth data is missing' do
        # Directly access the callback endpoint without going through OAuth flow
        # This simulates env['omniauth.auth'] being nil
        get '/auth/google_oauth2/callback'

        # Returns 422 because the rescue block catches the exception
        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Authentication failed')
      end
    end
  end

  describe 'DELETE /auth/logout' do
    it 'returns success message' do
      delete '/auth/logout'

      expect(response).to have_http_status(:ok)
      expect(json_response['message']).to eq('Logged out successfully')
    end

    it 'succeeds even without authentication' do
      # Logout should be idempotent - client just deletes tokens
      delete '/auth/logout'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /auth/failure' do
    it 'returns authentication failure message with details' do
      get '/auth/failure', params: { message: 'invalid_credentials', strategy: 'google_oauth2' }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response['error']).to eq('Authentication failed')
      expect(json_response['message']).to eq('invalid_credentials')
      expect(json_response['strategy']).to eq('google_oauth2')
    end

    it 'handles different failure messages' do
      get '/auth/failure', params: { message: 'access_denied', strategy: 'google_oauth2' }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response['message']).to eq('access_denied')
    end

    it 'handles missing parameters gracefully' do
      get '/auth/failure'

      expect(response).to have_http_status(:unauthorized)
      expect(json_response['error']).to eq('Authentication failed')
    end
  end
end
