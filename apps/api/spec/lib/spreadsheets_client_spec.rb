# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpreadsheetsClient do
  let(:access_token)   { "ya29.test_access_token" }
  let(:client)         { described_class.new(access_token) }
  let(:spreadsheet_id) { "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms" }

  let(:definition) do
    {
      "properties" => { "title" => "template title", "locale" => "en" },
      "sheets"     => [
        {
          "properties" => { "sheetId" => 100, "title" => "reports" },
          "data"       => [{ "startRow" => 0, "startColumn" => 0, "rowData" => [] }]
        }
      ]
    }
  end

  before do
    allow(JSON).to receive(:load_file)
      .with(SpreadsheetsClient::DEFINITION_PATH)
      .and_return(definition)
  end

  describe "#create_spreadsheet" do
    context "when the API returns 200" do
      before do
        stub_request(:post, "https://sheets.googleapis.com/v4/spreadsheets")
          .to_return(
            status:  200,
            body:    { "spreadsheetId" => spreadsheet_id }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends the correct Authorization header" do
        client.create_spreadsheet(title: "Damage Report 2024")

        expect(WebMock).to have_requested(:post, "https://sheets.googleapis.com/v4/spreadsheets")
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
      end

      it "sends the JSON definition with the title overridden" do
        client.create_spreadsheet(title: "Damage Report 2024")

        expect(WebMock).to have_requested(:post, "https://sheets.googleapis.com/v4/spreadsheets")
          .with { |req|
            body = JSON.parse(req.body)
            body["properties"]["title"] == "Damage Report 2024" &&
              body["sheets"] == definition["sheets"]
          }
      end

      it "returns the spreadsheet ID" do
        result = client.create_spreadsheet(title: "Damage Report 2024")

        expect(result).to eq(spreadsheet_id)
      end
    end

    context "when the API returns an error" do
      before do
        stub_request(:post, "https://sheets.googleapis.com/v4/spreadsheets")
          .to_return(status: 403, body: "Forbidden")
      end

      it "raises ApiError" do
        expect { client.create_spreadsheet(title: "Damage Report 2024") }
          .to raise_error(SpreadsheetsClient::ApiError, /403/)
      end
    end
  end

  describe "#protect_ranges" do
    let(:batch_update_url) { "https://sheets.googleapis.com/v4/spreadsheets/#{spreadsheet_id}:batchUpdate" }

    context "when requests is empty" do
      before do
        allow(JSON).to receive(:load_file)
          .with(SpreadsheetsClient::PROTECTION_PATH)
          .and_return({ "requests" => [] })
      end

      it "makes no HTTP request" do
        client.protect_ranges(spreadsheet_id:)

        expect(WebMock).not_to have_requested(:post, batch_update_url)
      end
    end

    context "when requests are present" do
      let(:protection) do
        {
          "requests" => [
            { "addProtectedRange" => { "protectedRange" => { "range" => { "sheetId" => 110 }, "warningOnly" => true } } }
          ]
        }
      end

      before do
        allow(JSON).to receive(:load_file)
          .with(SpreadsheetsClient::PROTECTION_PATH)
          .and_return(protection)
        stub_request(:post, batch_update_url)
          .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "calls batchUpdate with the protection requests" do
        client.protect_ranges(spreadsheet_id:)

        expect(WebMock).to have_requested(:post, batch_update_url)
          .with { |req| JSON.parse(req.body) == protection }
      end

      it "sends the correct Authorization header" do
        client.protect_ranges(spreadsheet_id:)

        expect(WebMock).to have_requested(:post, batch_update_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
      end
    end
  end

  describe "#append_rows" do
    let(:sheet_name) { "reports" }
    let(:rows)       { [%w[ハチ公 35.659054 139.700583 false 1700000000000]] }
    let(:append_url) do
      "https://sheets.googleapis.com/v4/spreadsheets/#{spreadsheet_id}/values/#{sheet_name}!A1:append"
    end

    context "when the API returns 200" do
      before do
        stub_request(:post, append_url)
          .with(query: { "valueInputOption" => "RAW" })
          .to_return(
            status:  200,
            body:    {}.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends the correct Authorization header" do
        client.append_rows(spreadsheet_id:, sheet_name:, rows:)

        expect(WebMock).to have_requested(:post, append_url)
          .with(query: { "valueInputOption" => "RAW" }, headers: { "Authorization" => "Bearer #{access_token}" })
      end

      it "sends valueInputOption=RAW as query parameter" do
        client.append_rows(spreadsheet_id:, sheet_name:, rows:)

        expect(WebMock).to have_requested(:post, append_url)
          .with(query: { "valueInputOption" => "RAW" })
      end

      it "sends rows as request body" do
        client.append_rows(spreadsheet_id:, sheet_name:, rows:)

        expect(WebMock).to have_requested(:post, append_url)
          .with(query: { "valueInputOption" => "RAW" }) { |req| JSON.parse(req.body) == { "values" => rows } }
      end
    end

    context "when the API returns an error" do
      before do
        stub_request(:post, append_url)
          .with(query: { "valueInputOption" => "RAW" })
          .to_return(status: 403, body: "Forbidden")
      end

      it "raises ApiError" do
        expect { client.append_rows(spreadsheet_id:, sheet_name:, rows:) }
          .to raise_error(SpreadsheetsClient::ApiError, /403/)
      end
    end
  end
end
