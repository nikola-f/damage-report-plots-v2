# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadBatchWorker do
  let(:token_key)    { "test-token-uuid" }
  let(:access_token) { "ya29.test_token" }
  let(:thread_ids)   { %w[t1 t2 t3] }
  let(:poller)       { instance_double(SqsPoller) }
  let(:token_store)  { instance_double(AccessTokenStore, fetch: access_token) }
  let(:sqs_client)   { instance_double(SqsClient, send_message: nil) }

  let(:portal) { PortalRecord.new(name: "ハチ公", latitude: "35.0", longitude: "139.0", owned: false, internal_date: 16999200) }
  let(:decoder) { instance_double(EmailHtmlDecoder) }
  let(:internal_date) { "1700000000000" }
  let(:gmail_message) { instance_double(GmailMessage, html_decoder: decoder, internal_date:) }
  let(:fetcher) { instance_double(GmailThreadBatchFetcher, call: [gmail_message]) }

  let(:message) do
    token_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: token_key)
    instance_double(
      Aws::SQS::Types::Message,
      body: JSON.generate(thread_ids),
      message_attributes: { "token_key" => token_attr }
    )
  end

  before do
    allow(SqsClient).to receive(:new).with(Settings.sqs_portal_queue_url).and_return(sqs_client)
    allow(SqsPoller).to receive(:new).and_return(poller)
    allow(poller).to receive(:poll).and_yield(message)
    allow(AccessTokenStore).to receive(:new).and_return(token_store)
    allow(GmailThreadBatchFetcher).to receive(:new).and_return(fetcher)
    allow(decoder).to receive(:extract_portals).with(internal_date:).and_return([portal])
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

    it "sends each PortalRecord to the portal SQS queue" do
      described_class.new.perform

      expect(sqs_client).to have_received(:send_message).with(portal)
    end

    it "reschedules itself after polling" do
      described_class.new.perform

      expect(described_class).to have_received(:perform_in).with(GmailThreadBatchWorker::POLL_INTERVAL)
    end

    context "when the same PortalRecord appears twice for the same token_key" do
      let(:fetcher) { instance_double(GmailThreadBatchFetcher, call: [gmail_message, gmail_message]) }

      it "sends the portal only once" do
        described_class.new.perform

        expect(sqs_client).to have_received(:send_message).with(portal).once
      end
    end

    context "when two messages have different token_keys with the same PortalRecord" do
      let(:other_token_key)    { "other-token-uuid" }
      let(:other_access_token) { "ya29.other_token" }
      let(:other_token_store)  { instance_double(AccessTokenStore, fetch: other_access_token) }
      let(:other_message) do
        token_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: other_token_key)
        instance_double(
          Aws::SQS::Types::Message,
          body: JSON.generate(thread_ids),
          message_attributes: { "token_key" => token_attr }
        )
      end

      before do
        allow(poller).to receive(:poll).and_yield(message).and_yield(other_message)
        allow(AccessTokenStore).to receive(:new).and_return(token_store, other_token_store)
        allow(GmailThreadBatchFetcher).to receive(:new).with(access_token: other_access_token).and_return(fetcher)
      end

      it "sends the portal twice (once per user)" do
        described_class.new.perform

        expect(sqs_client).to have_received(:send_message).with(portal).twice
      end
    end

    context "when html_decoder returns nil" do
      let(:gmail_message) { instance_double(GmailMessage, html_decoder: nil) }

      it "does not call send_message" do
        described_class.new.perform

        expect(sqs_client).not_to have_received(:send_message)
      end
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
