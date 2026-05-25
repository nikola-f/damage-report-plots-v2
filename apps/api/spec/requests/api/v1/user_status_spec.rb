# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/user_status", type: :request do
  let(:access_token_store)   { instance_double(UserStore, store: nil) }
  let(:spreadsheet_id_store) { instance_double(UserStore, fetch: "spreadsheet-id") }
  let(:last_synced_at_store) { instance_double(UserStore, fetch: "1744908000") }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:spreadsheet_id).and_return(spreadsheet_id_store)
    allow(UserStore).to receive(:last_synced_at).and_return(last_synced_at_store)
    allow(REDIS).to receive(:get).with(start_with("scope_spreadsheets:")).and_return(nil)
    allow(REDIS).to receive(:get).with(start_with("scope_sync:")).and_return(nil)
  end

  context "with active session" do
    before { login_as }

    it "returns spreadsheet_exists true when spreadsheet ID is stored" do
      get "/api/v1/user_status"

      expect(response).to have_http_status(:ok)
      expect(json_response["spreadsheet_exists"]).to be true
    end

    it "returns last_synced_at as integer" do
      get "/api/v1/user_status"

      expect(json_response["last_synced_at"]).to eq(1744908000)
    end

    it "returns null scope_expires_at when no scopes have been granted" do
      get "/api/v1/user_status"

      expect(json_response["scope_expires_at"]["spreadsheets"]).to be_nil
      expect(json_response["scope_expires_at"]["sync"]).to be_nil
    end

    context "when no spreadsheet exists" do
      before { allow(spreadsheet_id_store).to receive(:fetch).and_raise(KeyError) }

      it "returns spreadsheet_exists false" do
        get "/api/v1/user_status"

        expect(json_response["spreadsheet_exists"]).to be false
      end
    end

    context "when sync has never been run" do
      before { allow(last_synced_at_store).to receive(:fetch).and_raise(KeyError) }

      it "returns last_synced_at null" do
        get "/api/v1/user_status"

        expect(json_response["last_synced_at"]).to be_nil
      end
    end

    context "when spreadsheets scope has been granted" do
      let(:expires_at) { 1_744_567_890 }

      before do
        allow(REDIS).to receive(:get).with(start_with("scope_spreadsheets:")).and_return(expires_at.to_s)
      end

      it "returns the expiry epoch for spreadsheets" do
        get "/api/v1/user_status"

        expect(json_response["scope_expires_at"]["spreadsheets"]).to eq(expires_at)
        expect(json_response["scope_expires_at"]["sync"]).to be_nil
      end
    end

    context "when sync scope has been granted" do
      let(:expires_at) { 1_744_567_890 }

      before do
        allow(REDIS).to receive(:get).with(start_with("scope_spreadsheets:")).and_return(expires_at.to_s)
        allow(REDIS).to receive(:get).with(start_with("scope_sync:")).and_return(expires_at.to_s)
      end

      it "returns the expiry epoch for both spreadsheets and sync" do
        get "/api/v1/user_status"

        expect(json_response["scope_expires_at"]["spreadsheets"]).to eq(expires_at)
        expect(json_response["scope_expires_at"]["sync"]).to eq(expires_at)
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
