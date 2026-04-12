# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpreadsheetIdStore do
  let(:redis)   { instance_double(Redis) }
  let(:store)   { described_class.new(redis:) }
  let(:user_id) { "12345678901234567" }

  describe "#store" do
    before { allow(redis).to receive(:set) }

    it "stores the spreadsheet ID in Redis without TTL" do
      store.store(user_id, "spreadsheet-id-123")

      expect(redis).to have_received(:set)
        .with("spreadsheet_id:#{user_id}", "spreadsheet-id-123")
    end
  end

  describe "#fetch" do
    context "when the spreadsheet ID exists" do
      before do
        allow(redis).to receive(:get)
          .with("spreadsheet_id:#{user_id}")
          .and_return("spreadsheet-id-123")
      end

      it "returns the spreadsheet ID" do
        expect(store.fetch(user_id)).to eq("spreadsheet-id-123")
      end
    end

    context "when the spreadsheet ID does not exist" do
      before { allow(redis).to receive(:get).and_return(nil) }

      it "raises KeyError with the user_id in the message" do
        expect { store.fetch(user_id) }
          .to raise_error(KeyError, /#{user_id}/)
      end
    end
  end
end
