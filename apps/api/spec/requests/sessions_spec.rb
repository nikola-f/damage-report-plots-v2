# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:access_token_store) { instance_double(AccessTokenStore, store: "test-token-key-uuid") }

  before do
    allow(AccessTokenStore).to receive(:new).and_return(access_token_store)
  end

  describe "GET /auth/google_oauth2/callback" do
    context "with successful OAuth authentication" do
      before do
        mock_google_oauth_success
      end

      it "sets user session" do
        get "/auth/google_oauth2/callback"

        expect(response).to have_http_status(:ok)
        expect(session[:user_id]).to eq(test_user_id)
        expect(session[:email]).to eq(test_user_email)
        expect(session[:name]).to eq(test_user_name)
        expect(session[:token_key]).to eq("test-token-key-uuid")
      end

      it "returns user information" do
        get "/auth/google_oauth2/callback"

        expect(response).to have_http_status(:ok)
        user = json_response["user"]
        expect(user["id"]).to eq(test_user_id)
        expect(user["email"]).to eq(test_user_email)
        expect(user["name"]).to eq(test_user_name)
        expect(user["picture"]).to eq(test_user_picture)
      end

      it "stores the Google access token" do
        get "/auth/google_oauth2/callback"

        expect(access_token_store).to have_received(:store).with("google_access_token_123")
      end
    end

    context "with custom user data from Google" do
      before do
        mock_google_oauth_success(
          uid: "custom_id_789",
          email: "custom@example.com",
          name: "Custom User"
        )
      end

      it "uses the custom user data in session and response" do
        get "/auth/google_oauth2/callback"

        expect(session[:user_id]).to eq("custom_id_789")
        expect(json_response["user"]["email"]).to eq("custom@example.com")
        expect(json_response["user"]["name"]).to eq("Custom User")
      end
    end

    context "with missing OAuth data" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = nil
      end

      it "returns error when auth data is missing" do
        get "/auth/google_oauth2/callback"

        # Returns 422 because the rescue block catches the exception
        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to eq("Authentication failed")
      end
    end
  end

  describe "DELETE /auth/logout" do
    it "clears the session and returns success" do
      mock_google_oauth_success
      get "/auth/google_oauth2/callback"

      delete "/auth/logout"

      expect(response).to have_http_status(:ok)
      expect(json_response["message"]).to eq("Logged out successfully")
      expect(session[:user_id]).to be_nil
    end

    it "succeeds even without an active session" do
      delete "/auth/logout"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /auth/failure" do
    it "returns authentication failure message with details" do
      get "/auth/failure", params: { message: "invalid_credentials", strategy: "google_oauth2" }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Authentication failed")
      expect(json_response["message"]).to eq("invalid_credentials")
      expect(json_response["strategy"]).to eq("google_oauth2")
    end

    it "handles different failure messages" do
      get "/auth/failure", params: { message: "access_denied", strategy: "google_oauth2" }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["message"]).to eq("access_denied")
    end

    it "handles missing parameters gracefully" do
      get "/auth/failure"

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Authentication failed")
    end
  end
end
