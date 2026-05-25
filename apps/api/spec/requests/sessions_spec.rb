# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:access_token_store)       { instance_double(UserStore, store: nil) }
  let(:scope_spreadsheets_store) { instance_double(UserStore, store: nil) }
  let(:scope_sync_store)         { instance_double(UserStore, store: nil) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:scope_spreadsheets).and_return(scope_spreadsheets_store)
    allow(UserStore).to receive(:scope_sync).and_return(scope_sync_store)
  end

  describe "GET /auth/google_oauth2/callback" do
    context "with successful OAuth authentication" do
      before do
        mock_google_oauth_success
      end

      it "sets user session" do
        get "/auth/google_oauth2/callback"

        expect(session[:user_id]).to eq(test_user_id)
        expect(session[:email]).to eq(test_user_email)
        expect(session[:name]).to eq(test_user_name)
      end

      it "redirects to SPA root" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to("/")
      end

      it "stores the Google access token keyed by user_id" do
        get "/auth/google_oauth2/callback"

        expect(access_token_store).to have_received(:store).with(test_user_id, "google_access_token_123")
      end
    end

    context "as a scope upgrade (requested_scope present in session)" do
      before do
        login_as
        post "/auth/grant/spreadsheets"
      end

      it "updates the stored access token" do
        get "/auth/google_oauth2/callback"

        expect(access_token_store).to have_received(:store).with(test_user_id, "google_access_token_123").at_least(:once)
      end

      it "redirects to SPA root" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to("/")
      end

      it "stores the scope expiry epoch via UserStore" do
        get "/auth/google_oauth2/callback"

        expect(scope_spreadsheets_store).to have_received(:store).with(test_user_id, anything)
      end

      it "does not overwrite the user session" do
        get "/auth/google_oauth2/callback"

        expect(session[:user_id]).to eq(test_user_id)
        expect(session[:email]).to eq(test_user_email)
      end
    end

    context "as a scope upgrade with a different Google account" do
      before do
        login_as
        post "/auth/grant/spreadsheets"
        mock_google_oauth_success(uid: "different_google_id")
      end

      it "returns unauthorized" do
        get "/auth/google_oauth2/callback"

        expect(response).to have_http_status(:unauthorized)
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

      it "uses the custom user data in session" do
        get "/auth/google_oauth2/callback"

        expect(session[:user_id]).to eq("custom_id_789")
        expect(session[:email]).to eq("custom@example.com")
        expect(session[:name]).to eq("Custom User")
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
    it "returns authentication failure" do
      get "/auth/failure", params: { message: "invalid_credentials", strategy: "google_oauth2" }

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Authentication failed")
      expect(json_response).not_to have_key("message")
      expect(json_response).not_to have_key("strategy")
    end

    it "handles missing parameters gracefully" do
      get "/auth/failure"

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Authentication failed")
    end
  end

  describe "POST /auth/grant/spreadsheets" do
    context "without session" do
      it "returns unauthorized" do
        post "/auth/grant/spreadsheets"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with active session" do
      before { login_as }

      it "returns the authorization URL" do
        post "/auth/grant/spreadsheets"

        expect(response).to have_http_status(:ok)
        expect(json_response["authorization_url"]).to eq("/auth/google_oauth2")
      end

      it "stores the spreadsheets scope in the session" do
        post "/auth/grant/spreadsheets"

        expect(session[:requested_scope]).to eq(SessionsController::SPREADSHEETS_SCOPE)
      end
    end
  end

  describe "POST /auth/grant/sync" do
    context "without session" do
      it "returns unauthorized" do
        post "/auth/grant/sync"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with active session" do
      before { login_as }

      it "returns the authorization URL" do
        post "/auth/grant/sync"

        expect(response).to have_http_status(:ok)
        expect(json_response["authorization_url"]).to eq("/auth/google_oauth2")
      end

      it "stores the sync scope in the session" do
        post "/auth/grant/sync"

        expect(session[:requested_scope]).to eq(SessionsController::SYNC_SCOPE)
      end
    end
  end
end
