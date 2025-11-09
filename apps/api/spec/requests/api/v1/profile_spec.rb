require 'rails_helper'

RSpec.describe "GET /api/v1/profile", type: :request do
  before do
    # Mock credentials
    allow(Rails.application.credentials).to receive(:jwt_secret_key!).and_return('test_secret_key')
  end

  context 'with valid JWT token' do
    let(:payload) { { sub: '12345', email: 'test@example.com', name: 'Test User' } }
    let(:token) { JsonWebToken.encode(payload) }

    it 'returns user profile' do
      get '/api/v1/profile', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['message']).to eq('Access granted to protected resource')
      expect(json_response['user']['id']).to eq('12345')
      expect(json_response['user']['email']).to eq('test@example.com')
    end
  end

  context 'without token' do
    it 'returns unauthorized' do
      get '/api/v1/profile'

      expect(response).to have_http_status(:unauthorized)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to be_present
    end
  end

  context 'with invalid token' do
    it 'returns unauthorized' do
      get '/api/v1/profile', headers: { 'Authorization' => 'Bearer invalid.token.here' }

      expect(response).to have_http_status(:unauthorized)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('Invalid token')
    end
  end

  context 'with expired token' do
    let(:payload) { { sub: '12345', email: 'test@example.com', name: 'Test User' } }
    let(:expired_token) { JsonWebToken.encode(payload, 1.second.ago) }

    it 'returns unauthorized' do
      get '/api/v1/profile', headers: { 'Authorization' => "Bearer #{expired_token}" }

      expect(response).to have_http_status(:unauthorized)
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to include('Token expired')
    end
  end
end
