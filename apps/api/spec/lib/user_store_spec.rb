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

  describe ".last_synced_at" do
    let(:store) { described_class.last_synced_at(redis:) }

    include_examples "a user store", "last_synced_at"

    describe "#store" do
      before { allow(redis).to receive(:set) }

      it "stores the epoch time without TTL" do
        store.store(user_id, "1716624000")

        expect(redis).to have_received(:set)
          .with("last_synced_at:#{user_id}", "1716624000")
      end
    end
  end

  describe ".last_processed_at" do
    let(:store) { described_class.last_processed_at(redis:) }

    include_examples "a user store", "last_processed_at"

    describe "#store" do
      before { allow(redis).to receive(:set) }

      it "stores the epoch time without TTL" do
        store.store(user_id, "1716624000")

        expect(redis).to have_received(:set)
          .with("last_processed_at:#{user_id}", "1716624000")
      end
    end
  end

  describe ".scope_spreadsheets" do
    let(:store) { described_class.scope_spreadsheets(redis:) }

    include_examples "a user store", "scope_spreadsheets"

    describe "#store" do
      before { allow(redis).to receive(:set) }

      it "stores the expiry epoch with TTL" do
        store.store(user_id, "1744567890")

        expect(redis).to have_received(:set)
          .with("scope_spreadsheets:#{user_id}", "1744567890", ex: 3600)
      end
    end
  end

  describe ".scope_sync" do
    let(:store) { described_class.scope_sync(redis:) }

    include_examples "a user store", "scope_sync"

    describe "#store" do
      before { allow(redis).to receive(:set) }

      it "stores the expiry epoch with TTL" do
        store.store(user_id, "1744567890")

        expect(redis).to have_received(:set)
          .with("scope_sync:#{user_id}", "1744567890", ex: 3600)
      end
    end
  end

  describe ".threads_max_internal_date" do
    let(:store) { described_class.threads_max_internal_date(redis:) }

    include_examples "a user store", "threads_max_internal_date"

    describe "#delete" do
      before { allow(redis).to receive(:del).and_return(1) }

      it "deletes the key from Redis" do
        store.delete(user_id)

        expect(redis).to have_received(:del)
          .with("threads_max_internal_date:#{user_id}")
      end
    end
  end

  describe "counter stores" do
    counter_prefixes = %w[threads_found threads_processed portals_found portals_appended]

    counter_prefixes.each do |prefix|
      describe ".#{prefix}" do
        let(:store) { described_class.public_send(prefix, redis:) }

        include_examples "a user store", prefix

        it "is a CounterStore" do
          expect(store).to be_a(UserStore::CounterStore)
        end

        describe "#increment" do
          before { allow(redis).to receive(:incrby).and_return(7) }

          it "delegates to Redis INCRBY and returns the new total" do
            expect(store.increment(user_id, by: 3)).to eq(7)

            expect(redis).to have_received(:incrby).with("#{prefix}:#{user_id}", 3)
          end

          it "increments by 1 by default" do
            store.increment(user_id)

            expect(redis).to have_received(:incrby).with("#{prefix}:#{user_id}", 1)
          end
        end
      end
    end
  end

  describe "value stores" do
    it "do not respond to #increment" do
      expect(described_class.access_token(redis:)).not_to respond_to(:increment)
    end
  end
end
