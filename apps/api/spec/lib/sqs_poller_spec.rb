# frozen_string_literal: true

require "rails_helper"

RSpec.describe SqsPoller do
  let(:queue_url) { "https://sqs.test/queue" }
  let(:sqs)       { instance_double(SqsClient) }

  before { allow(SqsClient).to receive(:new).with(queue_url).and_return(sqs) }

  describe "#poll" do
    def build_message(receipt_handle)
      instance_double(Aws::SQS::Types::Message, receipt_handle:)
    end

    context "when there are messages" do
      let(:msg1) { build_message("rh-1") }
      let(:msg2) { build_message("rh-2") }

      before do
        allow(sqs).to receive(:receive_messages).and_return([msg1, msg2])
        allow(sqs).to receive(:delete_messages)
      end

      it "yields each message" do
        received = []
        described_class.new(queue_url:).poll { |msg| received << msg }

        expect(received).to eq([msg1, msg2])
      end

      it "deletes all messages after yielding" do
        described_class.new(queue_url:).poll { |_msg| }

        expect(sqs).to have_received(:delete_messages).with(%w[rh-1 rh-2])
      end
    end

    context "when message_attribute_names is specified" do
      before { allow(sqs).to receive(:receive_messages).and_return([]) }

      it "passes them to receive_messages" do
        described_class.new(queue_url:, message_attribute_names: ["token_key"]).poll { }

        expect(sqs).to have_received(:receive_messages).with(message_attribute_names: ["token_key"])
      end
    end

    context "when there are no messages" do
      before do
        allow(sqs).to receive(:receive_messages).and_return([])
        allow(sqs).to receive(:delete_messages)
      end

      it "does not call delete_messages" do
        described_class.new(queue_url:).poll { }

        expect(sqs).not_to have_received(:delete_messages)
      end
    end
  end
end
