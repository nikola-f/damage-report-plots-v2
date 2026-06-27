# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/plots", type: :request do
  let(:access_token_store)   { instance_double(UserStore, fetch: "ya29.token", store: nil) }
  let(:spreadsheet_id_store) { instance_double(UserStore, fetch: "spreadsheet-id") }
  let(:sheets_client)        { instance_double(SpreadsheetsClient) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(UserStore).to receive(:spreadsheet_id).and_return(spreadsheet_id_store)
    allow(SpreadsheetsClient).to receive(:new).and_return(sheets_client)
  end

  context "with active session" do
    before { login_as }

    context "when the plots sheet has rows" do
      before do
        allow(sheets_client).to receive(:get_values).and_return(
          [
            [35.681, 139.767, 1, 3, 1_700_000_002_000, 1_700_000_000_000],
            [34.702, 135.495, 0, 1, 1_700_000_005_000, ""]
          ]
        )
      end

      it "returns the rows as an array of 6-key objects" do
        get "/api/v1/plots"

        expect(response).to have_http_status(:ok)
        expect(json_response).to eq(
          [
            { "lat" => 35.681, "lng" => 139.767, "owned" => 1, "count" => 3,
              "latest" => 1_700_000_002_000, "oldest" => 1_700_000_000_000 },
            { "lat" => 34.702, "lng" => 135.495, "owned" => 0, "count" => 1,
              "latest" => 1_700_000_005_000, "oldest" => nil }
          ]
        )
      end

      it "reads the plotsExport named range" do
        get "/api/v1/plots"

        expect(sheets_client).to have_received(:get_values)
          .with(spreadsheet_id: "spreadsheet-id", range: "plotsExport")
      end
    end

    context "when the plots sheet is empty" do
      before { allow(sheets_client).to receive(:get_values).and_return([]) }

      it "returns an empty array" do
        get "/api/v1/plots"

        expect(response).to have_http_status(:ok)
        expect(json_response).to eq([])
      end
    end

    context "when trailing blank rows are present" do
      before do
        allow(sheets_client).to receive(:get_values).and_return(
          [[35.681, 139.767, 1, 1, 1_700_000_002_000, ""], []]
        )
      end

      it "excludes the blank rows" do
        get "/api/v1/plots"

        expect(json_response.size).to eq(1)
      end
    end

    context "when the spreadsheet ID is missing" do
      before { allow(spreadsheet_id_store).to receive(:fetch).and_raise(KeyError) }

      it "returns 401 with a reauthorization_required error" do
        get "/api/v1/plots"

        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("reauthorization_required")
      end
    end

    context "when the access token is missing (evicted from Redis)" do
      before { allow(access_token_store).to receive(:fetch).and_raise(KeyError) }

      it "returns 401 with a reauthorization_required error" do
        get "/api/v1/plots"

        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("reauthorization_required")
      end
    end

    context "when the Sheets API call fails" do
      before { allow(sheets_client).to receive(:get_values).and_raise(SpreadsheetsClient::ApiError) }

      it "returns 401 with a reauthorization_required error" do
        get "/api/v1/plots"

        expect(response).to have_http_status(:unauthorized)
        expect(json_response["error"]).to eq("reauthorization_required")
      end
    end
  end

  context "without session" do
    it "returns unauthorized" do
      get "/api/v1/plots"

      expect(response).to have_http_status(:unauthorized)
      expect(json_response["error"]).to eq("Unauthorized")
    end
  end
end
