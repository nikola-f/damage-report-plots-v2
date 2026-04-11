# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpreadsheetSyncWorker do
  let(:token_key)  { "test-token-uuid" }
  let(:record)     { DamageReportRecord.new(name: "ハチ公", latitude: "35.0", longitude: "139.0", owned: false, internal_date: 16999200) }
  let(:sqs_client) { instance_double(SqsClient) }

  let(:message) do
    token_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: token_key)
    instance_double(
      Aws::SQS::Types::Message,
      body: JSON.generate([record.to_h]),
      message_attributes: { AccessTokenStore::TOKEN_KEY_ATTR => token_attr }
    )
  end

  before do
    allow(SqsClient).to receive(:new).with(Settings.sqs_portal_queue_url).and_return(sqs_client)
    allow(sqs_client).to receive(:poll).and_yield(message)
    allow(described_class).to receive(:perform_in)
  end

  describe "#perform" do
    before { allow_any_instance_of(described_class).to receive(:process) }

    it "polls the portal queue with token_key attribute" do
      described_class.new.perform

      expect(sqs_client).to have_received(:poll).with(message_attribute_names: [AccessTokenStore::TOKEN_KEY_ATTR])
    end

    it "deserializes the message body into DamageReportRecord objects" do
      worker = described_class.new
      allow(worker).to receive(:process)

      worker.perform

      expect(worker).to have_received(:process).with(token_key:, records: [record])
    end

    it "reschedules itself after polling" do
      described_class.new.perform

      expect(described_class).to have_received(:perform_in).with(SpreadsheetSyncWorker::POLL_INTERVAL)
    end

    context "when an error occurs during processing" do
      before { allow(sqs_client).to receive(:poll).and_raise(RuntimeError) }

      it "still reschedules itself" do
        expect { described_class.new.perform }.to raise_error(RuntimeError)

        expect(described_class).to have_received(:perform_in).with(SpreadsheetSyncWorker::POLL_INTERVAL)
      end
    end
  end

  describe "#process" do
    let(:access_token)        { "ya29.test_access_token" }
    let(:spreadsheet_id)      { "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms" }
    let(:access_token_store)  { instance_double(AccessTokenStore, fetch: access_token) }
    let(:spreadsheet_id_store){ instance_double(SpreadsheetIdStore, fetch: spreadsheet_id) }
    let(:sheets_client)       { instance_double(SpreadsheetsClient, append_rows: nil) }
    let(:worker)              { described_class.new }

    before do
      allow(AccessTokenStore).to receive(:new).and_return(access_token_store)
      allow(SpreadsheetIdStore).to receive(:new).and_return(spreadsheet_id_store)
      allow(SpreadsheetsClient).to receive(:new).with(access_token).and_return(sheets_client)
      allow(worker).to receive(:to_row).and_return([])
    end

    it "fetches the access token using token_key" do
      worker.send(:process, token_key:, records: [record])

      expect(access_token_store).to have_received(:fetch).with(token_key)
    end

    it "fetches the spreadsheet ID using token_key" do
      worker.send(:process, token_key:, records: [record])

      expect(spreadsheet_id_store).to have_received(:fetch).with(token_key)
    end

    it "appends rows to the spreadsheet" do
      worker.send(:process, token_key:, records: [record])

      expect(sheets_client).to have_received(:append_rows).with(
        spreadsheet_id: spreadsheet_id,
        sheet_name:     SpreadsheetSyncWorker::SHEET_NAME,
        rows:           [[]]
      )
    end

    it "converts each record to a row via to_row" do
      worker.send(:process, token_key:, records: [record])

      expect(worker).to have_received(:to_row).with(record)
    end
  end

  describe "#to_row" do
    let(:worker)     { described_class.new }
    let(:now)        { Time.new(2024, 1, 15, 10, 30, 45) }

    before { allow(Time).to receive(:now).and_return(now) }

    subject(:row) { worker.send(:to_row, record) }

    it "returns 6 columns" do
      expect(row.length).to eq(6)
    end

    it "generates a deterministic Sqids ID from latitude and longitude" do
      id1 = worker.send(:to_row, record)[0]
      id2 = worker.send(:to_row, record)[0]

      expect(id1).to be_a(String).and(be_present)
      expect(id1).to eq(id2)
    end

    it "generates different IDs for different coordinates" do
      other = DamageReportRecord.new(name: "ハチ公", latitude: "35.1", longitude: "139.0", owned: false, internal_date: 16999200)

      expect(row[0]).not_to eq(worker.send(:to_row, other)[0])
    end

    it "places latitude in column 2" do
      expect(row[1]).to eq(record.latitude)
    end

    it "places longitude in column 3" do
      expect(row[2]).to eq(record.longitude)
    end

    it "places owned in column 4" do
      expect(row[3]).to eq(record.owned)
    end

    it "places internal_date and name comma-joined in column 5" do
      expect(row[4]).to eq("#{record.internal_date},#{record.name}")
    end

    it "places current time as YYMMddHHmmss integer in column 6" do
      expect(row[5]).to eq(240115103045)
    end
  end

  describe "Sidekiq options" do
    it "does not retry" do
      expect(described_class.sidekiq_options["retry"]).to eq(0)
    end
  end
end
