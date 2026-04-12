# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/sync", type: :request do
  let(:access_token_store)   { instance_double(UserStore, fetch: "ya29.token", store: nil) }
  let(:spreadsheet_id_store) { instance_double(UserStore, fetch: "spreadsheet-id", store: nil) }
  let(:sheets_client)        { instance_double(SpreadsheetsClient, create_spreadsheet: "new-spreadsheet-id", protect_ranges: nil) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:spreadsheet_id).and_return(spreadsheet_id_store)
    allow(SpreadsheetsClient).to receive(:new).and_return(sheets_client)
    allow(GmailThreadListWorker).to receive(:perform_async)
    allow(REDIS).to receive(:set).with(start_with("sync_queued_at:"), anything)
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

      it "records sync_queued_at in Redis" do
        post "/api/v1/sync"

        expect(REDIS).to have_received(:set).with("sync_queued_at:#{test_user_id}", anything)
      end
    end

    context "when spreadsheet does not exist" do
      before { allow(spreadsheet_id_store).to receive(:fetch).and_raise(KeyError) }

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

    context "with after_date parameter" do
      it "passes after_date to the worker" do
        post "/api/v1/sync", params: { after_date: "2024-01-01" }

        expect(GmailThreadListWorker).to have_received(:perform_async).with(test_user_id, "2024-01-01")
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
