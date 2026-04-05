# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadBatchWorker do
  let(:token_key)    { "test-token-uuid" }
  let(:access_token) { "ya29.test_token" }
  let(:thread_ids)   { %w[t1 t2 t3] }
  let(:poller)       { instance_double(SqsPoller) }
  let(:fetcher)      { instance_double(GmailThreadBatchFetcher, call: nil) }
  let(:token_store)  { instance_double(AccessTokenStore, fetch: access_token) }

  let(:message) do
    token_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: token_key)
    instance_double(
      Aws::SQS::Types::Message,
      body: JSON.generate(thread_ids),
      message_attributes: { "token_key" => token_attr }
    )
  end

  before do
    allow(SqsPoller).to receive(:new).and_return(poller)
    allow(poller).to receive(:poll).and_yield(message)
    allow(AccessTokenStore).to receive(:new).and_return(token_store)
    allow(GmailThreadBatchFetcher).to receive(:new).and_return(fetcher)
    allow(described_class).to receive(:perform_in)
  end

  describe "#perform" do
    it "creates SqsPoller with the report queue and token_key attribute" do
      described_class.new.perform

      expect(SqsPoller).to have_received(:new).with(
        queue_url: Settings.sqs_report_queue_url,
        message_attribute_names: ["token_key"]
      )
    end

    it "fetches the access token for each message" do
      described_class.new.perform

      expect(token_store).to have_received(:fetch).with(token_key)
    end

    it "calls GmailThreadBatchFetcher with access_token and thread_ids" do
      described_class.new.perform

      expect(GmailThreadBatchFetcher).to have_received(:new).with(access_token:)
      expect(fetcher).to have_received(:call).with(thread_ids)
    end

    it "reschedules itself after polling" do
      described_class.new.perform

      expect(described_class).to have_received(:perform_in).with(GmailThreadBatchWorker::POLL_INTERVAL)
    end

    context "when an error occurs during processing" do
      before { allow(poller).to receive(:poll).and_raise(RuntimeError) }

      it "still reschedules itself" do
        expect { described_class.new.perform }.to raise_error(RuntimeError)

        expect(described_class).to have_received(:perform_in).with(GmailThreadBatchWorker::POLL_INTERVAL)
      end
    end
  end

  describe "Sidekiq options" do
    it "does not retry" do
      expect(described_class.sidekiq_options["retry"]).to eq(0)
    end
  end
end
