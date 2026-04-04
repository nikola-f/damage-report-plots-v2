# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListWorker do
  let(:user_id)      { "user_001" }
  let(:email)        { "user@example.com" }
  let(:access_token) { "ya29.test_token" }

  describe "#perform" do
    let(:fetcher) { instance_double(GmailThreadListFetcher, call: []) }

    before do
      allow(GmailThreadListFetcher).to receive(:new).and_return(fetcher)
    end

    it "instantiates GmailThreadListFetcher with the correct arguments" do
      described_class.new.perform(user_id, email, access_token)

      expect(GmailThreadListFetcher).to have_received(:new).with(
        access_token:,
        user_id:,
        email:
      )
    end

    it "calls GmailThreadListFetcher#call with q: nil by default" do
      described_class.new.perform(user_id, email, access_token)
      expect(fetcher).to have_received(:call).with(q: nil)
    end

    it "passes q to GmailThreadListFetcher#call when provided" do
      described_class.new.perform(user_id, email, access_token, "subject:damage report")
      expect(fetcher).to have_received(:call).with(q: "subject:damage report")
    end
  end

  describe "Sidekiq options" do
    it "retries up to 3 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end
