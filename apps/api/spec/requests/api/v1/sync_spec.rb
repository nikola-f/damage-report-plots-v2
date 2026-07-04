# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/sync", type: :request do
  let(:access_token_store)    { instance_double(UserStore, fetch: "ya29.token", fetch_or_nil: "ya29.token", store: nil) }
  let(:spreadsheet_id_store)  { instance_double(UserStore, fetch_or_nil: "spreadsheet-id", store: nil) }
  let(:last_synced_at_store)  { instance_double(UserStore, store: nil) }
  let(:threads_found_store)     { instance_double(UserStore, store: nil) }
  let(:threads_processed_store) { instance_double(UserStore, store: nil) }
  let(:portals_found_store)     { instance_double(UserStore, store: nil) }
  let(:portals_appended_store)  { instance_double(UserStore, store: nil) }
  let(:threads_max_internal_date_store) { instance_double(UserStore) }
  let(:sheets_client)           { instance_double(SpreadsheetsClient, create_spreadsheet: "new-spreadsheet-id", protect_ranges: nil) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:spreadsheet_id).and_return(spreadsheet_id_store)
    allow(UserStore).to receive(:last_synced_at).and_return(last_synced_at_store)
    allow(UserStore).to receive(:threads_found).and_return(threads_found_store)
    allow(UserStore).to receive(:threads_processed).and_return(threads_processed_store)
    allow(UserStore).to receive(:portals_found).and_return(portals_found_store)
    allow(UserStore).to receive(:portals_appended).and_return(portals_appended_store)
    allow(UserStore).to receive(:threads_max_internal_date).and_return(threads_max_internal_date_store)
    allow(threads_max_internal_date_store).to receive(:fetch_or_nil).and_return(nil)
    allow(last_synced_at_store).to receive(:fetch_or_nil).and_return(nil)
    allow(SpreadsheetsClient).to receive(:new).and_return(sheets_client)
    allow(GmailThreadListWorker).to receive(:perform_async)
  end

  context "with active session" do
    before { login_as }

    context "when spreadsheet already exists" do
      it "returns 202 and enqueues the job" do
        post "/api/v1/sync"

        expect(response).to have_http_status(:accepted)
        expect(GmailThreadListWorker).to have_received(:perform_async).with(test_user_id, nil)
      end

      it "does not create a new spreadsheet" do
        post "/api/v1/sync"

        expect(sheets_client).not_to have_received(:create_spreadsheet)
      end

      it "records last_synced_at in UserStore" do
        post "/api/v1/sync"

        expect(last_synced_at_store).to have_received(:store).with(test_user_id, anything)
      end

      it "resets threads_found to 0 in UserStore" do
        post "/api/v1/sync"

        expect(threads_found_store).to have_received(:store).with(test_user_id, "0")
      end

      it "resets threads_processed to 0 in UserStore" do
        post "/api/v1/sync"

        expect(threads_processed_store).to have_received(:store).with(test_user_id, "0")
      end

      it "resets portals_found to 0 in UserStore" do
        post "/api/v1/sync"

        expect(portals_found_store).to have_received(:store).with(test_user_id, "0")
      end

      it "resets portals_appended to 0 in UserStore" do
        post "/api/v1/sync"

        expect(portals_appended_store).to have_received(:store).with(test_user_id, "0")
      end
    end

    context "when spreadsheet does not exist" do
      before { allow(spreadsheet_id_store).to receive(:fetch_or_nil).and_return(nil) }

      it "creates a spreadsheet and stores the ID" do
        post "/api/v1/sync"

        expect(sheets_client).to have_received(:create_spreadsheet)
        expect(sheets_client).to have_received(:protect_ranges).with(spreadsheet_id: "new-spreadsheet-id")
        expect(spreadsheet_id_store).to have_received(:store).with(test_user_id, "new-spreadsheet-id")
      end

      it "returns 202 and enqueues the job" do
        post "/api/v1/sync"

        expect(response).to have_http_status(:accepted)
        expect(GmailThreadListWorker).to have_received(:perform_async).with(test_user_id, nil)
      end
    end

    context "when the access token is missing (evicted from Redis)" do
      before { allow(access_token_store).to receive(:fetch_or_nil).and_return(nil) }

      it "returns 401 with a reauthorization_required error" do
        post "/api/v1/sync"

        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("reauthorization_required")
      end

      it "does not enqueue the worker" do
        post "/api/v1/sync"

        expect(GmailThreadListWorker).not_to have_received(:perform_async)
      end

      it "does not create a spreadsheet or reset counters" do
        post "/api/v1/sync"

        expect(sheets_client).not_to have_received(:create_spreadsheet)
        expect(last_synced_at_store).not_to have_received(:store)
      end
    end

    context "when a previous sync started within the minimum interval" do
      before do
        allow(last_synced_at_store).to receive(:fetch_or_nil)
          .and_return((Time.now.to_i - 5).to_s)
      end

      it "returns 429 with a rate_limited error and a Retry-After header" do
        post "/api/v1/sync"

        expect(response).to have_http_status(:too_many_requests)
        expect(json_response["error"]).to eq("rate_limited")
        expect(response.headers["Retry-After"].to_i).to be > 0
      end

      it "does not enqueue the worker or reset counters" do
        post "/api/v1/sync"

        expect(GmailThreadListWorker).not_to have_received(:perform_async)
        expect(last_synced_at_store).not_to have_received(:store)
      end
    end

    context "when the minimum interval has elapsed since the last sync" do
      before do
        allow(last_synced_at_store).to receive(:fetch_or_nil)
          .and_return((Time.now.to_i - Settings.sync_min_interval - 1).to_s)
      end

      it "returns 202 and enqueues the job" do
        post "/api/v1/sync"

        expect(response).to have_http_status(:accepted)
        expect(GmailThreadListWorker).to have_received(:perform_async).with(test_user_id, nil)
      end
    end

    context "when threads_max_internal_date exists" do
      before do
        allow(threads_max_internal_date_store).to receive(:fetch_or_nil)
          .and_return((Time.utc(2024, 1, 1).to_i * 1000).to_s)
      end

      it "passes the stored internal date (ms) as an epoch in seconds to the worker" do
        post "/api/v1/sync"

        expect(GmailThreadListWorker).to have_received(:perform_async)
          .with(test_user_id, Time.utc(2024, 1, 1).to_i)
      end
    end
  end

  context "without session" do
    it "returns unauthorized" do
      post "/api/v1/sync"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
