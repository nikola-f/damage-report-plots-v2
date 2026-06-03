# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/user_status", type: :request do
  let(:access_token_store)        { instance_double(UserStore, store: nil) }
  let(:spreadsheet_id_store)      { instance_double(UserStore, fetch: "spreadsheet-id") }
  let(:last_synced_at_store)      { instance_double(UserStore, fetch: "1744908000") }
  let(:scope_spreadsheets_store)  { instance_double(UserStore) }
  let(:scope_sync_store)          { instance_double(UserStore) }
  let(:threads_found_store)       { instance_double(UserStore, fetch: "1500") }
  let(:threads_processed_store)   { instance_double(UserStore, fetch: "320") }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:spreadsheet_id).and_return(spreadsheet_id_store)
    allow(UserStore).to receive(:last_synced_at).and_return(last_synced_at_store)
    allow(UserStore).to receive(:scope_spreadsheets).and_return(scope_spreadsheets_store)
    allow(UserStore).to receive(:scope_sync).and_return(scope_sync_store)
    allow(UserStore).to receive(:threads_found).and_return(threads_found_store)
    allow(UserStore).to receive(:threads_processed).and_return(threads_processed_store)
    allow(scope_spreadsheets_store).to receive(:fetch).and_raise(KeyError)
    allow(scope_sync_store).to receive(:fetch).and_raise(KeyError)
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

    it "returns threads_found as integer" do
      get "/api/v1/user_status"

      expect(json_response["threads_found"]).to eq(1500)
    end

    it "returns threads_processed as integer" do
      get "/api/v1/user_status"

      expect(json_response["threads_processed"]).to eq(320)
    end

    context "when threads_found has not been stored" do
      before { allow(threads_found_store).to receive(:fetch).and_raise(KeyError) }

      it "returns threads_found null" do
        get "/api/v1/user_status"

        expect(json_response["threads_found"]).to be_nil
      end
    end

    context "when threads_processed has not been stored" do
      before { allow(threads_processed_store).to receive(:fetch).and_raise(KeyError) }

      it "returns threads_processed null" do
        get "/api/v1/user_status"

        expect(json_response["threads_processed"]).to be_nil
      end
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
        allow(scope_spreadsheets_store).to receive(:fetch).and_return(expires_at.to_s)
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
        allow(scope_spreadsheets_store).to receive(:fetch).and_return(expires_at.to_s)
        allow(scope_sync_store).to receive(:fetch).and_return(expires_at.to_s)
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
