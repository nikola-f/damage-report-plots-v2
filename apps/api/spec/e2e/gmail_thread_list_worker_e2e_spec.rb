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
#   GOOGLE_TEST_REFRESH_TOKEN            - Long-lived OAuth refresh token (scope: gmail.readonly)
#   GOOGLE_CLIENT_ID                     - OAuth client ID
#   GOOGLE_CLIENT_SECRET                 - OAuth client secret
#   SETTINGS__SQS_THREAD_IDS_QUEUE_URL  - SQS FIFO queue URL (LocalStack or real AWS)
#   SETTINGS__REDIS_URL                  - Valkey URL (e.g. redis://localhost:6380/0)
#   AWS_ENDPOINT_URL                     - LocalStack endpoint (e.g. http://localhost:4566)
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY - dummy credentials for LocalStack
#
# Start services before running:
#   docker run -d -p 4566:4566 localstack/localstack:3
#   AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
#     aws --endpoint-url=http://localhost:4566 --region us-east-1 sqs create-queue \
#     --queue-name test-report-queue.fifo \
#     --attributes FifoQueue=true,ContentBasedDeduplication=false
#   docker run -d -p 6380:6379 valkey/valkey
#
# Run:
#   export BW_SESSION=$(bw unlock --raw)
#   bin/e2e spec/e2e/gmail_thread_list_worker_e2e_spec.rb

RSpec.describe GmailThreadListWorker, :e2e do
  before(:all) { WebMock.allow_net_connect! }
  after(:all)  { WebMock.disable_net_connect! }

  let(:access_token) { fetch_google_access_token }
  let(:queue_url)    { Settings.sqs_thread_ids_queue_url }
  let(:user_id)      { Digest::SHA256.hexdigest(access_token) }
  let(:token_hash)   { user_id }

  let(:sqs) do
    options = { region: ENV.fetch("AWS_DEFAULT_REGION", "us-east-1") }
    # LocalStack の場合は endpoint を上書き
    if queue_url.start_with?("http://localhost")
      options[:endpoint]    = "http://localhost:4566"
      options[:credentials] = Aws::Credentials.new("test", "test")
    end
    Aws::SQS::Client.new(**options)
  end

  before do
    sqs.purge_queue(queue_url: queue_url)
    UserStore.access_token.store(user_id, access_token)
  end

  # quota キーは削除しない。TTL (60s) で自然にリセットされることで、
  # Gmail 側のレートリミッターと Redis カウンターの同期が保たれる。

  describe "#perform" do
    it "fetches Gmail threads matching the query and enqueues thread IDs to SQS as a JSON array" do
      d = Date.today - 7
      described_class.new.perform(user_id, Time.utc(d.year, d.month, d.day).to_i)

      messages = sqs.receive_message(
        queue_url: queue_url,
        max_number_of_messages: 10,
        message_attribute_names: [UserStore::USER_ID_ATTR]
      ).messages

      expect(messages).not_to be_empty

      thread_ids = JSON.parse(messages.first.body)
      expect(thread_ids).to be_an(Array)
      expect(thread_ids.first).to be_present
      expect(messages.first.message_attributes[UserStore::USER_ID_ATTR].string_value).to eq(user_id)
    end

    it "increments Redis quota counters" do
      d = Date.today - 7
      described_class.new.perform(user_id, Time.utc(d.year, d.month, d.day).to_i)

      expect(REDIS.get("gmail_quota:project").to_i).to be > 0
      expect(REDIS.get("gmail_quota:user:#{token_hash}").to_i).to be > 0
    end

    context "when there are no matching threads" do
      it "does not enqueue any messages to SQS" do
        future_epoch = Time.now.to_i + (365 * 24 * 3600)
        described_class.new.perform(user_id, future_epoch)

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
