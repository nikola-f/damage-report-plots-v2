# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserStore do
  let(:redis)   { instance_double(Redis) }
  let(:user_id) { "12345678901234567" }

  shared_examples "a user store" do |key_prefix|
    describe "#fetch" do
      context "when the value exists" do
        before { allow(redis).to receive(:get).with("#{key_prefix}:#{user_id}").and_return("stored-value") }

        it "returns the value" do
          expect(store.fetch(user_id)).to eq("stored-value")
        end
      end

      context "when the value does not exist" do
        before { allow(redis).to receive(:get).and_return(nil) }

        it "raises KeyError" do
          expect { store.fetch(user_id) }.to raise_error(KeyError)
        end
      end
    end
  end

  describe ".access_token" do
    let(:store) { described_class.access_token(redis:) }

    include_examples "a user store", "access_token"

    describe "#store" do
      before { allow(redis).to receive(:set) }

      it "stores the token with TTL" do
        store.store(user_id, "ya29.token")

        expect(redis).to have_received(:set)
          .with("access_token:#{user_id}", "ya29.token", ex: 3600)
      end
    end
  end

  describe ".spreadsheet_id" do
    let(:store) { described_class.spreadsheet_id(redis:) }

    include_examples "a user store", "spreadsheet_id"

    describe "#store" do
      before { allow(redis).to receive(:set) }

      it "stores the spreadsheet ID without TTL" do
        store.store(user_id, "spreadsheet-id-123")

        expect(redis).to have_received(:set)
          .with("spreadsheet_id:#{user_id}", "spreadsheet-id-123")
      end
    end
  end
end
