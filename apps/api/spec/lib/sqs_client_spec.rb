# frozen_string_literal: true

require "rails_helper"
require "digest"

RSpec.describe SqsClient do
  let(:queue_url)        { "https://sqs.ap-northeast-1.amazonaws.com/123456789012/test-queue.fifo" }
  let(:aws_client)       { instance_double(Aws::SQS::Client) }
  let(:client)           { described_class.new(queue_url, client: aws_client) }
  let(:task)             { ReportTask.new(thread_id: "thread_001") }
  let(:task_body)        { JSON.generate(task.to_h) }
  let(:task_dedup_id)    { Digest::SHA256.hexdigest(task_body) }

  describe "#send_message" do
    it "sends message with deduplication_id, group_id, and empty attributes" do
      expect(aws_client).to receive(:send_message).with(
        queue_url: queue_url,
        message_body: task_body,
        message_group_id: "default",
        message_deduplication_id: task_dedup_id,
        message_attributes: {}
      )

      client.send_message(task)
    end

    context "with attributes" do
      it "converts String values to SQS String type" do
        expect(aws_client).to receive(:send_message).with(
          hash_including(
            message_attributes: {
              "source" => { data_type: "String", string_value: "gmail" }
            }
          )
        )

        client.send_message(task, attributes: { "source" => "gmail" })
      end

      it "converts Numeric values to SQS Number type" do
        expect(aws_client).to receive(:send_message).with(
          hash_including(
            message_attributes: {
              "retry_count" => { data_type: "Number", string_value: "3" }
            }
          )
        )

        client.send_message(task, attributes: { "retry_count" => 3 })
      end

      it "handles mixed types" do
        expect(aws_client).to receive(:send_message).with(
          hash_including(
            message_attributes: {
              "source" => { data_type: "String", string_value: "gmail" },
              "retry_count" => { data_type: "Number", string_value: "0" }
            }
          )
        )

        client.send_message(task, attributes: { "source" => "gmail", "retry_count" => 0 })
      end
    end

    context "with custom message_group_id" do
      let(:client) { described_class.new(queue_url, message_group_id: "user_001", client: aws_client) }

      it "uses the specified group_id" do
        expect(aws_client).to receive(:send_message).with(
          hash_including(message_group_id: "user_001")
        )

        client.send_message(task)
      end
    end
  end

  describe "#send_messages" do
    context "when all thread_ids fit within MAX_MESSAGE_SIZE" do
      let(:thread_ids) { %w[t1 t2 t3] }

      it "packs all thread_ids into a single SQS message as a JSON array" do
        body = JSON.generate(thread_ids)

        expect(aws_client).to receive(:send_message_batch).once.with(
          queue_url: queue_url,
          entries: [{
            id: "0",
            message_body: body,
            message_group_id: "default",
            message_deduplication_id: Digest::SHA256.hexdigest(body),
            message_attributes: {}
          }]
        )

        client.send_messages(thread_ids)
      end

      it "applies attributes to the message" do
        allow(aws_client).to receive(:send_message_batch)

        client.send_messages(thread_ids, attributes: { "source" => "gmail", "retry_count" => 0 })

        expect(aws_client).to have_received(:send_message_batch).with(
          hash_including(
            entries: include(
              hash_including(message_attributes: {
                               "source" => { data_type: "String", string_value: "gmail" },
                               "retry_count" => { data_type: "Number", string_value: "0" }
                             })
            )
          )
        )
      end
    end

    context "when thread_ids exceed MAX_MESSAGE_SIZE" do
      # JSON.generate(["t1","t2"]) = '["t1","t2"]' = 11 bytes > 10
      # JSON.generate(["t1"])      = '["t1"]'       =  6 bytes <= 10
      before { stub_const("SqsClient::MAX_MESSAGE_SIZE", 10) }

      let(:thread_ids) { %w[t1 t2 t3] }

      it "splits into multiple SQS messages, each within the size limit" do
        allow(aws_client).to receive(:send_message_batch)

        client.send_messages(thread_ids)

        expect(aws_client).to have_received(:send_message_batch).once.with(
          hash_including(entries: have_attributes(size: 3))
        )
      end

      it "each message body is a JSON array within the size limit" do
        allow(aws_client).to receive(:send_message_batch) do |args|
          args[:entries].each do |entry|
            expect(entry[:message_body].bytesize).to be <= 10
            expect(JSON.parse(entry[:message_body])).to be_an(Array)
          end
        end

        client.send_messages(thread_ids)
      end
    end

    context "when chunks exceed 10 (SQS batch API limit)" do
      # Force each thread_id into its own chunk by setting a very small size limit.
      # JSON.generate(["t1"]) = '["t1"]' = 6 bytes
      before { stub_const("SqsClient::MAX_MESSAGE_SIZE", 6) }

      let(:thread_ids) { Array.new(25) { |i| format("t%02d", i) } }

      it "batches SQS API calls in groups of 10 chunks" do
        expect(aws_client).to receive(:send_message_batch).exactly(3).times

        client.send_messages(thread_ids)
      end

      it "resets entry IDs within each batch" do
        allow(aws_client).to receive(:send_message_batch)

        client.send_messages(thread_ids)

        expect(aws_client).to have_received(:send_message_batch).with(
          hash_including(entries: include(hash_including(id: "0"), hash_including(id: "9")))
        ).at_least(:once)
      end
    end
  end

  describe "#receive_messages" do
    def build_message(n)
      instance_double(Aws::SQS::Types::Message,
                      body: JSON.generate({ index: n }),
                      receipt_handle: "receipt-handle-#{n}")
    end

    def build_response(*messages)
      instance_double(Aws::SQS::Types::ReceiveMessageResult, messages: messages)
    end

    it "uses MAX_RECEIVE_MESSAGES as the limit" do
      stub_const("SqsClient::MAX_RECEIVE_MESSAGES", 10)
      msgs = Array.new(10) { |i| build_message(i) }

      expect(aws_client).to receive(:receive_message).once.with(
        queue_url: queue_url,
        max_number_of_messages: 10,
        wait_time_seconds: 20
      ).and_return(build_response(*msgs))

      expect(client.receive_messages).to eq(msgs)
    end

    it "loops in batches of 10" do
      stub_const("SqsClient::MAX_RECEIVE_MESSAGES", 15)
      batch1 = Array.new(10) { |i| build_message(i) }
      batch2 = Array.new(5)  { |i| build_message(i + 10) }

      expect(aws_client).to receive(:receive_message).with(
        hash_including(max_number_of_messages: 10, wait_time_seconds: 20)
      ).and_return(build_response(*batch1))

      expect(aws_client).to receive(:receive_message).with(
        hash_including(max_number_of_messages: 5, wait_time_seconds: 20)
      ).and_return(build_response(*batch2))

      expect(client.receive_messages.size).to eq(15)
    end

    context "with custom wait_time_seconds" do
      let(:client) { described_class.new(queue_url, wait_time_seconds: 5, client: aws_client) }

      it "uses the specified wait time" do
        stub_const("SqsClient::MAX_RECEIVE_MESSAGES", 10)
        msgs = Array.new(10) { |i| build_message(i) }

        expect(aws_client).to receive(:receive_message).once.with(
          hash_including(wait_time_seconds: 5)
        ).and_return(build_response(*msgs))

        client.receive_messages
      end
    end

    context "when queue returns empty before max is reached" do
      it "stops early and returns collected messages" do
        msg = build_message(1)

        expect(aws_client).to receive(:receive_message).once
                                                       .and_return(build_response(msg))
        expect(aws_client).to receive(:receive_message).once
                                                       .and_return(build_response)

        result = client.receive_messages
        expect(result).to eq([msg])
      end
    end
  end

  describe "#delete_messages" do
    context "with a single receipt handle" do
      it "deletes the message" do
        expect(aws_client).to receive(:delete_message_batch).with(
          queue_url: queue_url,
          entries: [{ id: "0", receipt_handle: "handle-001" }]
        )

        client.delete_messages("handle-001")
      end
    end

    context "with multiple receipt handles as arguments" do
      it "deletes all messages in a single batch" do
        expect(aws_client).to receive(:delete_message_batch).once.with(
          queue_url: queue_url,
          entries: [
            { id: "0", receipt_handle: "handle-001" },
            { id: "1", receipt_handle: "handle-002" }
          ]
        )

        client.delete_messages("handle-001", "handle-002")
      end
    end

    context "with an array of receipt handles" do
      it "deletes all messages in a single batch" do
        expect(aws_client).to receive(:delete_message_batch).once

        client.delete_messages(%w[handle-001 handle-002])
      end
    end

    context "with more than 10 receipt handles" do
      let(:handles) { Array.new(15) { |i| "handle-#{i}" } }

      it "splits into multiple batches of up to 10" do
        expect(aws_client).to receive(:delete_message_batch).exactly(2).times

        client.delete_messages(*handles)
      end
    end
  end
end
