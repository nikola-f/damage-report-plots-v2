# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/profile", type: :request do
  let(:access_token_store) { instance_double(UserStore, store: nil) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
  end

  context "with active session" do
    before { login_as }

    it "returns user profile with complete user data" do
      get "/api/v1/profile"

      expect(response).to have_http_status(:ok)
      expect(json_response["message"]).to eq("Access granted to protected resource")
      expect(json_response["user"]["id"]).to eq(test_user_id)
      expect(json_response["user"]["email"]).to eq(test_user_email)
      expect(json_response["user"]["name"]).to eq(test_user_name)
    end
  end

  context "without session" do
    it "returns unauthorized" do
      get "/api/v1/profile"

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized")
    end
  end
end
