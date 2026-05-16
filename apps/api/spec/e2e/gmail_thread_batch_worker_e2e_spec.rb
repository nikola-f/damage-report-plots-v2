# frozen_string_literal: true

require "rails_helper"

# E2E test for GmailThreadBatchWorker#perform.
#
# Requires the following external services to be running:
#   - Gmail API (real HTTP calls)
#   - LocalStack or real AWS SQS (two FIFO queues: thread_ids and reports)
#   - Docker Valkey (Redis-compatible, matching production ElastiCache Valkey)
#
# Required environment variables:
#   GOOGLE_TEST_REFRESH_TOKEN            - Long-lived OAuth refresh token (scope: gmail.readonly)
#   GOOGLE_CLIENT_ID                     - OAuth client ID
#   GOOGLE_CLIENT_SECRET                 - OAuth client secret
#   SETTINGS__SQS_THREAD_IDS_QUEUE_URL  - SQS FIFO queue URL for thread IDs
#   SETTINGS__SQS_REPORTS_QUEUE_URL     - SQS FIFO queue URL for reports
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
#   AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
#     aws --endpoint-url=http://localhost:4566 --region us-east-1 sqs create-queue \
#     --queue-name test-reports-queue.fifo \
#     --attributes FifoQueue=true,ContentBasedDeduplication=false
#   docker run -d -p 6380:6379 valkey/valkey
#
# Run:
#   export BW_SESSION=$(bw unlock --raw)
#   bin/e2e spec/e2e/gmail_thread_batch_worker_e2e_spec.rb

RSpec.describe GmailThreadBatchWorker, :e2e do
  SEED_THREAD_COUNT = 3

  before(:all) do
    WebMock.allow_net_connect!

    thread_ids_url = Settings.sqs_thread_ids_queue_url
    sqs_opts = { region: ENV.fetch("AWS_DEFAULT_REGION", "us-east-1") }
    if thread_ids_url.start_with?("http://localhost")
      sqs_opts[:endpoint]    = "http://localhost:4566"
      sqs_opts[:credentials] = Aws::Credentials.new("test", "test")
    end
    setup_sqs = Aws::SQS::Client.new(**sqs_opts)

    [thread_ids_url, Settings.sqs_reports_queue_url].each do |url|
      setup_sqs.create_queue(
        queue_name: url.split("/").last,
        attributes: { "FifoQueue" => "true", "ContentBasedDeduplication" => "false" }
      )
    end
  end

  after(:all) { WebMock.disable_net_connect! }

  let(:access_token)   { fetch_google_access_token }
  let(:user_id)        { Digest::SHA256.hexdigest(access_token) }
  let(:thread_ids_url) { Settings.sqs_thread_ids_queue_url }
  let(:reports_url)    { Settings.sqs_reports_queue_url }

  let(:sqs) do
    options = { region: ENV.fetch("AWS_DEFAULT_REGION", "us-east-1") }
    if thread_ids_url.start_with?("http://localhost")
      options[:endpoint]    = "http://localhost:4566"
      options[:credentials] = Aws::Credentials.new("test", "test")
    end
    Aws::SQS::Client.new(**options)
  end

  before do
    sqs.purge_queue(queue_url: thread_ids_url)
    sqs.purge_queue(queue_url: reports_url)
    UserStore.access_token.store(user_id, access_token)
    allow(described_class).to receive(:perform_in)
  end

  # quota キーは削除しない。TTL (60s) で自然にリセットされることで、
  # Gmail 側のレートリミッターと Redis カウンターの同期が保たれる。

  describe "#perform" do
    context "when thread_ids queue has messages" do
      before do
        # GmailThreadListWorker を経由せず直接シードして quota 消費を抑える。
        # list_threads(10 units) + batch_get × SEED_THREAD_COUNT(40 units each) のみ消費する。
        query      = IngressDamageReportQuery.new(after_date: (Date.today - 7).iso8601)
        thread_ids = GmailClient.new(access_token, redis: REDIS)
                                .list_threads(q: query.to_s)
                                .fetch("threads", [])
                                .first(SEED_THREAD_COUNT)
                                .map { |t| t["id"] }

        skip "No matching Gmail threads in the last 7 days" if thread_ids.empty?

        SqsClient.new(thread_ids_url).send_messages(
          thread_ids,
          attributes: { UserStore::USER_ID_ATTR => user_id }
        )
      end

      it "processes threads and sends any found portals to the reports queue with correct user_id" do
        described_class.new.perform

        messages = sqs.receive_message(
          queue_url: reports_url,
          max_number_of_messages: 10,
          wait_time_seconds: 2,
          message_attribute_names: [UserStore::USER_ID_ATTR]
        ).messages

        messages.each do |message|
          portals = JSON.parse(message.body)
          expect(portals).to be_an(Array)
          expect(message.message_attributes[UserStore::USER_ID_ATTR].string_value).to eq(user_id)
        end
      end
    end

    context "when thread_ids queue is empty" do
      it "does not enqueue any messages to reports queue" do
        described_class.new.perform

        messages = sqs.receive_message(
          queue_url: reports_url,
          max_number_of_messages: 1,
          wait_time_seconds: 1
        ).messages

        expect(messages).to be_empty
      end
    end
  end
end
