# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListWorker do
  let(:token_key)    { "test-token-uuid" }
  let(:access_token) { "ya29.test_token" }
  let(:token_store)  { instance_double(AccessTokenStore, fetch_and_delete: access_token) }
  let(:sqs_client)   { instance_double(SqsClient, send_messages: nil) }
  let(:thread_ids)   { %w[t1 t2] }
  let(:fetcher)      { instance_double(GmailThreadListFetcher, call: thread_ids) }

  before do
    allow(AccessTokenStore).to receive(:new).and_return(token_store)
    allow(SqsClient).to receive(:new).with(Settings.sqs_report_queue_url).and_return(sqs_client)
    allow(GmailThreadListFetcher).to receive(:new).and_return(fetcher)
  end

  describe "#perform" do
    it "fetches the access token from AccessTokenStore" do
      described_class.new.perform(token_key, "2024-01-01")

      expect(token_store).to have_received(:fetch_and_delete).with(token_key)
    end

    it "calls GmailThreadListFetcher with the Ingress damage report query" do
      described_class.new.perform(token_key, "2024-01-01")

      expect(fetcher).to have_received(:call).with(
        q: IngressDamageReportQuery.new(after_date: "2024-01-01").to_s
      )
    end

    it "sends thread IDs to SQS" do
      described_class.new.perform(token_key, "2024-01-01")

      expect(sqs_client).to have_received(:send_messages).with(%w[t1 t2])
    end

    context "when there are no thread IDs" do
      let(:fetcher) { instance_double(GmailThreadListFetcher, call: []) }

      it "does not call send_messages" do
        described_class.new.perform(token_key, "2024-01-01")

        expect(sqs_client).not_to have_received(:send_messages)
      end
    end
  end

  describe "Sidekiq options" do
    it "retries up to 3 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end
