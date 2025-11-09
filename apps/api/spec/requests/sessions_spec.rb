require 'rails_helper'

RSpec.describe "Sessions", type: :request do
  before do
    # Mock credentials
    allow(Rails.application.credentials).to receive(:jwt_secret_key!).and_return('test_secret_key')
    allow(Rails.application.credentials).to receive(:jwt_refresh_secret!).and_return('test_refresh_secret_key')
  end

  describe "POST /auth/refresh" do
    context 'with valid refresh token' do
      let(:payload) { { sub: '12345', email: 'test@example.com', name: 'Test User', picture: 'https://example.com/pic.jpg' } }
      let(:refresh_token) { JsonWebToken.encode_refresh_token(payload) }

      it 'returns a new access token' do
        post '/auth/refresh', headers: { 'Authorization' => "Bearer #{refresh_token}" }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['access_token']).to be_present
        expect(json_response['token_type']).to eq('Bearer')
        expect(json_response['expires_in']).to eq(900)
      end
    end

    context 'with invalid refresh token' do
      it 'returns unauthorized' do
        post '/auth/refresh', headers: { 'Authorization' => 'Bearer invalid.token' }

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Invalid refresh token')
      end
    end

    context 'with expired refresh token' do
      let(:payload) { { sub: '12345', email: 'test@example.com', name: 'Test User' } }
      let(:expired_refresh_token) { JsonWebToken.encode_refresh_token(payload, 1.second.ago) }

      it 'returns unauthorized' do
        post '/auth/refresh', headers: { 'Authorization' => "Bearer #{expired_refresh_token}" }

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Refresh token expired')
      end
    end

    context 'without token' do
      it 'returns bad request' do
        post '/auth/refresh'

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Refresh token required')
      end
    end

    context 'with access token instead of refresh token' do
      let(:payload) { { sub: '12345', email: 'test@example.com', name: 'Test User' } }
      let(:access_token) { JsonWebToken.encode(payload) }

      it 'returns unauthorized' do
        post '/auth/refresh', headers: { 'Authorization' => "Bearer #{access_token}" }

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        # Access tokens use a different secret, so they fail to decode with refresh secret
        expect(json_response['error']).to eq('Invalid refresh token')
      end
    end
  end

  describe "DELETE /auth/logout" do
    it 'returns success message' do
      delete '/auth/logout'

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Logged out successfully')
    end
  end

  describe "GET /auth/failure" do
    it 'returns authentication failure message' do
      get '/auth/failure', params: { message: 'invalid_credentials', strategy: 'google_oauth2' }

      expect(response).to have_http_status(:unauthorized)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Authentication failed')
      expect(json_response['message']).to eq('invalid_credentials')
      expect(json_response['strategy']).to eq('google_oauth2')
    end
  end
end
