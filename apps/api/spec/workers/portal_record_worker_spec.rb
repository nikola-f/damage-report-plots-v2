# frozen_string_literal: true

require "rails_helper"

RSpec.describe PortalRecordWorker do
  let(:token_key)       { "test-token-uuid" }
  let(:portal)          { PortalRecord.new(name: "ハチ公", latitude: "35.0", longitude: "139.0", owned: false, internal_date: 16999200) }
  let(:sqs_client)      { instance_double(SqsClient) }

  let(:message) do
    token_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: token_key)
    instance_double(
      Aws::SQS::Types::Message,
      body: JSON.generate([portal.to_h]),
      message_attributes: { AccessTokenStore::TOKEN_KEY_ATTR => token_attr }
    )
  end

  before do
    allow(SqsClient).to receive(:new).with(Settings.sqs_portal_queue_url).and_return(sqs_client)
    allow(sqs_client).to receive(:poll).and_yield(message)
    allow(described_class).to receive(:perform_in)
  end

  describe "#perform" do
    it "polls the portal queue with token_key attribute" do
      described_class.new.perform

      expect(sqs_client).to have_received(:poll).with(message_attribute_names: [AccessTokenStore::TOKEN_KEY_ATTR])
    end

    it "deserializes the message body into PortalRecord objects" do
      worker = described_class.new
      allow(worker).to receive(:process)

      worker.perform

      expect(worker).to have_received(:process).with(token_key:, portals: [portal])
    end

    it "reschedules itself after polling" do
      described_class.new.perform

      expect(described_class).to have_received(:perform_in).with(PortalRecordWorker::POLL_INTERVAL)
    end

    context "when an error occurs during processing" do
      before { allow(sqs_client).to receive(:poll).and_raise(RuntimeError) }

      it "still reschedules itself" do
        expect { described_class.new.perform }.to raise_error(RuntimeError)

        expect(described_class).to have_received(:perform_in).with(PortalRecordWorker::POLL_INTERVAL)
      end
    end
  end

  describe "Sidekiq options" do
    it "does not retry" do
      expect(described_class.sidekiq_options["retry"]).to eq(0)
    end
  end
end
