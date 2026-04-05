# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessTokenStore do
  let(:redis) { instance_double(Redis) }
  let(:store) { described_class.new(redis:) }

  describe "#store" do
    before { allow(redis).to receive(:set) }

    it "stores the token in Redis with TTL and returns a UUID key" do
      key = store.store("ya29.token")

      expect(redis).to have_received(:set)
        .with("access_token:#{key}", "ya29.token", ex: AccessTokenStore::TTL)
    end

    it "returns a UUID-format key" do
      key = store.store("ya29.token")

      expect(key).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "returns a different key on each call" do
      keys = Array.new(2) { store.store("ya29.token") }

      expect(keys.uniq.size).to eq(2)
    end
  end

  describe "#fetch" do
    context "when the token exists" do
      before do
        allow(redis).to receive(:get).with("access_token:some-key").and_return("ya29.token")
        allow(redis).to receive(:getdel)
      end

      it "returns the token" do
        expect(store.fetch("some-key")).to eq("ya29.token")
      end

      it "does not delete the token" do
        store.fetch("some-key")

        expect(redis).not_to have_received(:getdel)
      end
    end

    context "when the token does not exist or has expired" do
      before { allow(redis).to receive(:get).and_return(nil) }

      it "raises KeyError with the key in the message" do
        expect { store.fetch("missing-key") }
          .to raise_error(KeyError, /missing-key/)
      end
    end
  end

  describe "#fetch_and_delete" do
    context "when the token exists" do
      before do
        allow(redis).to receive(:getdel)
          .with("access_token:some-key")
          .and_return("ya29.token")
      end

      it "returns the token" do
        expect(store.fetch_and_delete("some-key")).to eq("ya29.token")
      end

      it "deletes the token atomically via GETDEL" do
        store.fetch_and_delete("some-key")

        expect(redis).to have_received(:getdel).with("access_token:some-key")
      end
    end

    context "when the token does not exist or has expired" do
      before { allow(redis).to receive(:getdel).and_return(nil) }

      it "raises KeyError with the key in the message" do
        expect { store.fetch_and_delete("missing-key") }
          .to raise_error(KeyError, /missing-key/)
      end
    end
  end
end
