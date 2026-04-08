# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpreadsheetsClient do
  let(:access_token)   { "ya29.test_access_token" }
  let(:client)         { described_class.new(access_token) }
  let(:spreadsheet_id) { "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms" }

  let(:sheet)    { SpreadsheetTemplate::Sheet.new(name: "Attacks", headers: %w[Date Portal Latitude Longitude]) }
  let(:template) { SpreadsheetTemplate.new(sheets: [sheet]) }

  let(:expected_body) do
    {
      "properties" => { "title" => "Damage Report 2024" },
      "sheets"     => [
        {
          "properties" => { "title" => "Attacks" },
          "data"       => [{
            "startRow"    => 0,
            "startColumn" => 0,
            "rowData"     => [{
              "values" => [
                { "userEnteredValue" => { "stringValue" => "Date" } },
                { "userEnteredValue" => { "stringValue" => "Portal" } },
                { "userEnteredValue" => { "stringValue" => "Latitude" } },
                { "userEnteredValue" => { "stringValue" => "Longitude" } }
              ]
            }]
          }]
        }
      ]
    }
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
        client.create_spreadsheet(title: "Damage Report 2024", template:)

        expect(WebMock).to have_requested(:post, "https://sheets.googleapis.com/v4/spreadsheets")
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
      end

      it "sends the correct request body" do
        client.create_spreadsheet(title: "Damage Report 2024", template:)

        expect(WebMock).to have_requested(:post, "https://sheets.googleapis.com/v4/spreadsheets")
          .with { |req| JSON.parse(req.body) == expected_body }
      end

      it "returns the spreadsheet ID" do
        result = client.create_spreadsheet(title: "Damage Report 2024", template:)

        expect(result).to eq(spreadsheet_id)
      end
    end

    context "when the API returns an error" do
      before do
        stub_request(:post, "https://sheets.googleapis.com/v4/spreadsheets")
          .to_return(status: 403, body: "Forbidden")
      end

      it "raises ApiError" do
        expect { client.create_spreadsheet(title: "Damage Report 2024", template:) }
          .to raise_error(SpreadsheetsClient::ApiError, /403/)
      end
    end
  end
end
