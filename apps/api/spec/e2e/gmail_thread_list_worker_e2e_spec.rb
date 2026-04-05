# frozen_string_literal: true

require "rails_helper"

# E2E test for GmailThreadListWorker#perform.
#
# Requires the following external services to be running:
#   - Gmail API (real HTTP calls)
#   - LocalStack or real AWS SQS (FIFO queue)
#   - Docker Valkey (Redis-compatible, matching production ElastiCache Valkey)
#
# Required environment variables:
#   TEST_GMAIL_ACCESS_TOKEN  - Valid Gmail OAuth access token (scope: gmail.readonly)
#   SQS_REPORT_QUEUE_URL     - SQS FIFO queue URL (LocalStack or real AWS)
#   REDIS_URL                - Valkey URL (e.g. redis://localhost:6380/0)
#
# Start services before running:
#   docker run -d -p 4566:4566 localstack/localstack
#   aws --endpoint-url=http://localhost:4566 sqs create-queue \
#     --queue-name test-report-queue.fifo \
#     --attributes FifoQueue=true,ContentBasedDeduplication=false
#   docker run -d -p 6380:6379 valkey/valkey
#
# Run:
#   TEST_GMAIL_ACCESS_TOKEN=ya29.xxx \
#   SQS_REPORT_QUEUE_URL=http://localhost:4566/000000000000/test-report-queue.fifo \
#   bundle exec rspec spec/e2e/gmail_thread_list_worker_e2e_spec.rb

RSpec.describe GmailThreadListWorker, :e2e do
  before(:all) { WebMock.allow_net_connect! }
  after(:all)  { WebMock.disable_net_connect! }

  let(:access_token) { ENV.fetch("TEST_GMAIL_ACCESS_TOKEN") }
  let(:queue_url)    { Settings.sqs_report_queue_url }
  let(:token_hash)   { Digest::SHA256.hexdigest(access_token) }
  let(:token_key)    { AccessTokenStore.new.store(access_token) }

  let(:sqs) do
    options = { region: ENV.fetch("AWS_DEFAULT_REGION", "us-east-1") }
    # LocalStack の場合は endpoint を上書き
    if queue_url.start_with?("http://localhost")
      options[:endpoint]    = "http://localhost:4566"
      options[:credentials] = Aws::Credentials.new("test", "test")
    end
    Aws::SQS::Client.new(**options)
  end

  after do
    REDIS.del("gmail_quota:project", "gmail_quota:user:#{token_hash}")
  end

  describe "#perform" do
    it "fetches Gmail threads matching the query and enqueues thread IDs to SQS as a JSON array" do
      described_class.new.perform(token_key, (Date.today - 7).iso8601)

      messages = sqs.receive_message(
        queue_url: queue_url,
        max_number_of_messages: 10,
        message_attribute_names: ["token_key"]
      ).messages

      expect(messages).not_to be_empty

      thread_ids = JSON.parse(messages.first.body)
      expect(thread_ids).to be_an(Array)
      expect(thread_ids.first).to be_present
      expect(messages.first.message_attributes["token_key"].string_value).to eq(token_key)
    end

    it "increments Redis quota counters" do
      described_class.new.perform(token_key, (Date.today - 7).iso8601)

      expect(REDIS.get("gmail_quota:project").to_i).to be > 0
      expect(REDIS.get("gmail_quota:user:#{token_hash}").to_i).to be > 0
    end

    context "when there are no matching threads" do
      it "does not enqueue any messages to SQS" do
        described_class.new.perform(token_key, "2000-01-01")

        messages = sqs.receive_message(
          queue_url: queue_url,
          max_number_of_messages: 1,
          wait_time_seconds: 1
        ).messages

        expect(messages).to be_empty
      end
    end
  end
end
