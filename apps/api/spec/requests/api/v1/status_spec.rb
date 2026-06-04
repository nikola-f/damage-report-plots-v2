# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/status", type: :request do
  # --- UserStatusData stubs ---
  let(:access_token_store)      { instance_double(UserStore, store: nil) }
  let(:spreadsheet_id_store)    { instance_double(UserStore, fetch: "spreadsheet-id") }
  let(:last_synced_at_store)    { instance_double(UserStore, fetch: "1744908000") }
  let(:scope_spreadsheets_store){ instance_double(UserStore) }
  let(:scope_sync_store)        { instance_double(UserStore) }
  let(:threads_found_store)     { instance_double(UserStore, fetch: "1500") }
  let(:threads_processed_store) { instance_double(UserStore, fetch: "320") }
  let(:portals_found_store)              { instance_double(UserStore, fetch: "980") }
  let(:portals_appended_store)           { instance_double(UserStore, fetch: "750") }
  let(:threads_max_internal_date_store)  { instance_double(UserStore, fetch: "1700000000000") }

  # --- ApplicationStatusData stubs ---
  let(:report_sqs) { instance_double(SqsClient, queue_depth: { available: 3, in_flight: 1 }) }
  let(:portal_sqs) { instance_double(SqsClient, queue_depth: { available: 0, in_flight: 2 }) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:spreadsheet_id).and_return(spreadsheet_id_store)
    allow(UserStore).to receive(:last_synced_at).and_return(last_synced_at_store)
    allow(UserStore).to receive(:scope_spreadsheets).and_return(scope_spreadsheets_store)
    allow(UserStore).to receive(:scope_sync).and_return(scope_sync_store)
    allow(UserStore).to receive(:threads_found).and_return(threads_found_store)
    allow(UserStore).to receive(:threads_processed).and_return(threads_processed_store)
    allow(UserStore).to receive(:portals_found).and_return(portals_found_store)
    allow(UserStore).to receive(:portals_appended).and_return(portals_appended_store)
    allow(UserStore).to receive(:threads_max_internal_date).and_return(threads_max_internal_date_store)
    allow(scope_spreadsheets_store).to receive(:fetch).and_raise(KeyError)
    allow(scope_sync_store).to receive(:fetch).and_raise(KeyError)

    allow(SqsClient).to receive(:new).with(Settings.sqs_thread_ids_queue_url).and_return(report_sqs)
    allow(SqsClient).to receive(:new).with(Settings.sqs_reports_queue_url).and_return(portal_sqs)
    allow(REDIS).to receive(:get).with("gmail_quota:project").and_return("5000")
    allow(REDIS).to receive(:ttl).with("gmail_quota:project").and_return(42)
  end

  context "with active session" do
    before { login_as }

    it "returns 200" do
      get "/api/v1/status"

      expect(response).to have_http_status(:ok)
    end

    describe "user section" do
      it "returns spreadsheet_exists true when spreadsheet ID is stored" do
        get "/api/v1/status"

        expect(json_response["user"]["spreadsheet_exists"]).to be true
      end

      it "returns last_synced_at as integer" do
        get "/api/v1/status"

        expect(json_response["user"]["last_synced_at"]).to eq(1744908000)
      end

      it "returns threads_found as integer" do
        get "/api/v1/status"

        expect(json_response["user"]["threads_found"]).to eq(1500)
      end

      it "returns threads_processed as integer" do
        get "/api/v1/status"

        expect(json_response["user"]["threads_processed"]).to eq(320)
      end

      it "returns portals_found as integer" do
        get "/api/v1/status"

        expect(json_response["user"]["portals_found"]).to eq(980)
      end

      it "returns portals_appended as integer" do
        get "/api/v1/status"

        expect(json_response["user"]["portals_appended"]).to eq(750)
      end

      it "returns null scope_expires_at when no scopes have been granted" do
        get "/api/v1/status"

        expect(json_response["user"]["scope_expires_at"]["spreadsheets"]).to be_nil
        expect(json_response["user"]["scope_expires_at"]["sync"]).to be_nil
      end

      context "when no spreadsheet exists" do
        before { allow(spreadsheet_id_store).to receive(:fetch).and_raise(KeyError) }

        it "returns spreadsheet_exists false" do
          get "/api/v1/status"

          expect(json_response["user"]["spreadsheet_exists"]).to be false
        end
      end

      context "when sync has never been run" do
        before { allow(last_synced_at_store).to receive(:fetch).and_raise(KeyError) }

        it "returns last_synced_at null" do
          get "/api/v1/status"

          expect(json_response["user"]["last_synced_at"]).to be_nil
        end
      end

      context "when threads_found has not been stored" do
        before { allow(threads_found_store).to receive(:fetch).and_raise(KeyError) }

        it "returns threads_found null" do
          get "/api/v1/status"

          expect(json_response["user"]["threads_found"]).to be_nil
        end
      end

      context "when portals_appended has not been stored" do
        before { allow(portals_appended_store).to receive(:fetch).and_raise(KeyError) }

        it "returns portals_appended null" do
          get "/api/v1/status"

          expect(json_response["user"]["portals_appended"]).to be_nil
        end
      end

      it "returns threads_max_internal_date as integer" do
        get "/api/v1/status"

        expect(json_response["user"]["threads_max_internal_date"]).to eq(1_700_000_000_000)
      end

      context "when threads_max_internal_date has not been stored" do
        before { allow(threads_max_internal_date_store).to receive(:fetch).and_raise(KeyError) }

        it "returns threads_max_internal_date null" do
          get "/api/v1/status"

          expect(json_response["user"]["threads_max_internal_date"]).to be_nil
        end
      end

      context "when sync scope has been granted" do
        let(:expires_at) { 1_744_567_890 }

        before do
          allow(scope_spreadsheets_store).to receive(:fetch).and_return(expires_at.to_s)
          allow(scope_sync_store).to receive(:fetch).and_return(expires_at.to_s)
        end

        it "returns the expiry epoch for both spreadsheets and sync" do
          get "/api/v1/status"

          expect(json_response["user"]["scope_expires_at"]["spreadsheets"]).to eq(expires_at)
          expect(json_response["user"]["scope_expires_at"]["sync"]).to eq(expires_at)
        end
      end
    end

    describe "app section" do
      it "returns gmail quota usage" do
        get "/api/v1/status"

        quota = json_response["app"]["gmail_quota"]
        expect(quota["used"]).to eq(5000)
        expect(quota["limit"]).to eq(GmailClient::PER_PROJECT_LIMIT)
        expect(quota["remaining"]).to eq(GmailClient::PER_PROJECT_LIMIT - 5000)
        expect(quota["window_seconds"]).to eq(GmailClient::QUOTA_WINDOW)
        expect(quota["resets_in_seconds"]).to eq(42)
      end

      it "returns SQS queue depth per queue" do
        get "/api/v1/status"

        expect(json_response["app"]["sqs_queues"]["thread_ids"]).to eq(4)
        expect(json_response["app"]["sqs_queues"]["reports"]).to eq(2)
      end

      context "when no quota has been used yet" do
        before do
          allow(REDIS).to receive(:get).with("gmail_quota:project").and_return(nil)
          allow(REDIS).to receive(:ttl).with("gmail_quota:project").and_return(-2)
        end

        it "reports zero usage and zero resets_in_seconds" do
          get "/api/v1/status"

          quota = json_response["app"]["gmail_quota"]
          expect(quota["used"]).to eq(0)
          expect(quota["remaining"]).to eq(GmailClient::PER_PROJECT_LIMIT)
          expect(quota["resets_in_seconds"]).to eq(0)
        end
      end
    end
  end

  context "without session" do
    it "returns unauthorized" do
      get "/api/v1/status"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
