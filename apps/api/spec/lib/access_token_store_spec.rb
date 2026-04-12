# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessTokenStore do
  let(:redis)   { instance_double(Redis) }
  let(:store)   { described_class.new(redis:) }
  let(:user_id) { "12345678901234567" }

  describe "#store" do
    before { allow(redis).to receive(:set) }

    it "stores the token in Redis with TTL keyed by user_id" do
      store.store(user_id, "ya29.token")

      expect(redis).to have_received(:set)
        .with("access_token:#{user_id}", "ya29.token", ex: AccessTokenStore::TTL)
    end
  end

  describe "#fetch" do
    context "when the token exists" do
      before do
        allow(redis).to receive(:get).with("access_token:#{user_id}").and_return("ya29.token")
        allow(redis).to receive(:getdel)
      end

      it "returns the token" do
        expect(store.fetch(user_id)).to eq("ya29.token")
      end

      it "does not delete the token" do
        store.fetch(user_id)

        expect(redis).not_to have_received(:getdel)
      end
    end

    context "when the token does not exist or has expired" do
      before { allow(redis).to receive(:get).and_return(nil) }

      it "raises KeyError with the user_id in the message" do
        expect { store.fetch(user_id) }
          .to raise_error(KeyError, /#{user_id}/)
      end
    end
  end

  describe "#fetch_and_delete" do
    context "when the token exists" do
      before do
        allow(redis).to receive(:getdel)
          .with("access_token:#{user_id}")
          .and_return("ya29.token")
      end

      it "returns the token" do
        expect(store.fetch_and_delete(user_id)).to eq("ya29.token")
      end

      it "deletes the token atomically via GETDEL" do
        store.fetch_and_delete(user_id)

        expect(redis).to have_received(:getdel).with("access_token:#{user_id}")
      end
    end

    context "when the token does not exist or has expired" do
      before { allow(redis).to receive(:getdel).and_return(nil) }

      it "raises KeyError with the user_id in the message" do
        expect { store.fetch_and_delete(user_id) }
          .to raise_error(KeyError, /#{user_id}/)
      end
    end
  end
end
