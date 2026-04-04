# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/profile", type: :request do
  before do
    mock_jwt_credentials
  end

  context "with valid JWT token" do
    let(:token) { generate_access_token }

    it "returns user profile with complete user data" do
      authenticated_get "/api/v1/profile", token

      expect(response).to have_http_status(:ok)
      expect(json_response["message"]).to eq("Access granted to protected resource")
      expect(json_response["user"]["id"]).to eq(test_user_id)
      expect(json_response["user"]["email"]).to eq(test_user_email)
      expect(json_response["user"]["name"]).to eq(test_user_name)
    end
  end

  context "without token" do
    it "returns unauthorized with specific error message" do
      get "/api/v1/profile"

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized - Invalid token")
    end
  end

  context "with invalid token" do
    it "returns unauthorized with specific error message" do
      get "/api/v1/profile", headers: { "Authorization" => "Bearer invalid.token.here" }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized - Invalid token")
    end
  end

  context "with expired token" do
    let(:expired_token) { generate_expired_access_token }

    it "returns unauthorized with token expired error" do
      authenticated_get "/api/v1/profile", expired_token

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized - Token expired")
    end
  end

  # Security Tests
  context "with tampered token" do
    let(:token) { generate_access_token }
    let(:tampered_token) { tamper_with_token(token) }

    it "rejects token with invalid signature" do
      authenticated_get "/api/v1/profile", tampered_token

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized - Invalid token")
    end
  end

  # Edge Cases
  context "with malformed Authorization header" do
    let(:token) { generate_access_token }

    it "accepts token without Bearer prefix (lenient parsing)" do
      # Our implementation is lenient and accepts tokens without Bearer prefix
      get "/api/v1/profile", headers: { "Authorization" => token }

      expect(response).to have_http_status(:ok)
      expect(json_response["user"]["id"]).to eq(test_user_id)
    end

    it "rejects empty Authorization header" do
      get "/api/v1/profile", headers: { "Authorization" => "" }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized - Invalid token")
    end

    it "rejects Authorization header with only Bearer" do
      get "/api/v1/profile", headers: { "Authorization" => "Bearer" }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized - Invalid token")
    end

    it "handles Authorization header with extra whitespace" do
      # With "Bearer  token  ", split(' ').last actually returns the last non-empty part
      # In Ruby, "Bearer  token  ".split(' ') => ["Bearer", "token"]
      get "/api/v1/profile", headers: { "Authorization" => "Bearer  #{token}  " }

      # Actually succeeds because split handles multiple spaces correctly
      expect(response).to have_http_status(:ok)
      expect(json_response["user"]["id"]).to eq(test_user_id)
    end
  end

  context "with case-insensitive Bearer prefix" do
    let(:token) { generate_access_token }

    it "accepts lowercase bearer prefix (lenient parsing)" do
      # Our implementation doesn't enforce case sensitivity on the prefix
      get "/api/v1/profile", headers: { "Authorization" => "bearer #{token}" }

      expect(response).to have_http_status(:ok)
      expect(json_response["user"]["id"]).to eq(test_user_id)
    end
  end
end
