# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/user_status", type: :request do
  let(:access_token_store)   { instance_double(UserStore, store: nil) }
  let(:spreadsheet_id_store) { instance_double(UserStore, fetch: "spreadsheet-id") }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:spreadsheet_id).and_return(spreadsheet_id_store)
    allow(REDIS).to receive(:get).with(start_with("sync_queued_at:")).and_return("2026-04-12T17:00:00Z")
  end

  context "with active session" do
    before { login_as }

    it "returns spreadsheet_exists true when spreadsheet ID is stored" do
      get "/api/v1/user_status"

      expect(response).to have_http_status(:ok)
      expect(json_response["spreadsheet_exists"]).to be true
    end

    it "returns scope_level 1 after login" do
      get "/api/v1/user_status"

      expect(json_response["scope_level"]).to eq(1)
    end

    it "returns sync_queued_at from Redis" do
      get "/api/v1/user_status"

      expect(json_response["sync_queued_at"]).to eq("2026-04-12T17:00:00Z")
    end

    context "when no spreadsheet exists" do
      before { allow(spreadsheet_id_store).to receive(:fetch).and_raise(KeyError) }

      it "returns spreadsheet_exists false" do
        get "/api/v1/user_status"

        expect(json_response["spreadsheet_exists"]).to be false
      end
    end

    context "when sync has not been queued yet" do
      before { allow(REDIS).to receive(:get).with(start_with("sync_queued_at:")).and_return(nil) }

      it "returns sync_queued_at null" do
        get "/api/v1/user_status"

        expect(json_response["sync_queued_at"]).to be_nil
      end
    end

    context "after scope upgrade to level 2" do
      before do
        post "/auth/grant/spreadsheets"
        get "/auth/google_oauth2/callback"
      end

      it "returns scope_level 2" do
        get "/api/v1/user_status"

        expect(json_response["scope_level"]).to eq(2)
      end
    end

    context "after scope upgrade to level 3" do
      before do
        post "/auth/grant/sync"
        get "/auth/google_oauth2/callback"
      end

      it "returns scope_level 3" do
        get "/api/v1/user_status"

        expect(json_response["scope_level"]).to eq(3)
      end
    end
  end

  context "without session" do
    it "returns unauthorized" do
      get "/api/v1/user_status"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
