# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpreadsheetIdStore do
  let(:redis) { instance_double(Redis) }
  let(:store) { described_class.new(redis:) }

  describe "#store" do
    before { allow(redis).to receive(:set) }

    it "stores the spreadsheet ID in Redis with the token_key" do
      store.store("some-token-key", "spreadsheet-id-123")

      expect(redis).to have_received(:set)
        .with("spreadsheet_id:some-token-key", "spreadsheet-id-123")
    end
  end

  describe "#fetch" do
    context "when the spreadsheet ID exists" do
      before do
        allow(redis).to receive(:get)
          .with("spreadsheet_id:some-token-key")
          .and_return("spreadsheet-id-123")
      end

      it "returns the spreadsheet ID" do
        expect(store.fetch("some-token-key")).to eq("spreadsheet-id-123")
      end
    end

    context "when the spreadsheet ID does not exist" do
      before { allow(redis).to receive(:get).and_return(nil) }

      it "raises KeyError with the key in the message" do
        expect { store.fetch("missing-key") }
          .to raise_error(KeyError, /missing-key/)
      end
    end
  end
end
