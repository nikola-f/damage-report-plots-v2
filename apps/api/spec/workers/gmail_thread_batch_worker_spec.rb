# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadBatchWorker do
  let(:user_id)      { "user_001" }
  let(:access_token) { "ya29.test_token" }
  let(:thread_ids)   { %w[t1 t2 t3] }

  describe "#perform" do
    let(:fetcher) { instance_double(GmailThreadBatchFetcher, call: []) }

    before do
      allow(GmailThreadBatchFetcher).to receive(:new).and_return(fetcher)
    end

    it "instantiates GmailThreadBatchFetcher with the correct arguments" do
      described_class.new.perform(user_id, access_token, thread_ids)

      expect(GmailThreadBatchFetcher).to have_received(:new).with(
        access_token:,
        user_id:
      )
    end

    it "calls GmailThreadBatchFetcher#call with thread_ids" do
      described_class.new.perform(user_id, access_token, thread_ids)
      expect(fetcher).to have_received(:call).with(thread_ids)
    end
  end

  describe "Sidekiq options" do
    it "retries up to 3 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end
