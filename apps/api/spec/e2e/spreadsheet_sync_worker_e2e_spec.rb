# frozen_string_literal: true

require "rails_helper"

# E2E test for SpreadsheetSyncWorker#perform.
#
# Requires the following external services to be running:
#   - Google Sheets API (real HTTP calls; scope: spreadsheets)
#   - LocalStack or real AWS SQS (FIFO queue: reports)
#   - Docker Valkey (Redis-compatible)
#
# Required environment variables:
#   GOOGLE_TEST_REFRESH_TOKEN           - Long-lived OAuth refresh token (scope: gmail.readonly spreadsheets)
#   GOOGLE_CLIENT_ID                    - OAuth client ID
#   GOOGLE_CLIENT_SECRET                - OAuth client secret
#   GOOGLE_TEST_SPREADSHEET_ID          - Existing Google Spreadsheet ID with a "reports" sheet
#   SETTINGS__SQS_REPORTS_QUEUE_URL    - SQS FIFO queue URL for reports
#   SETTINGS__REDIS_URL                 - Valkey URL (e.g. redis://localhost:6380/0)
#   AWS_ENDPOINT_URL                    - LocalStack endpoint (e.g. http://localhost:4566)
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY - dummy credentials for LocalStack
#
# Start services before running:
#   docker run -d -p 4566:4566 localstack/localstack:3
#   AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
#     aws --endpoint-url=http://localhost:4566 --region us-east-1 sqs create-queue \
#     --queue-name test-reports-queue.fifo \
#     --attributes FifoQueue=true,ContentBasedDeduplication=false
#   docker run -d -p 6380:6379 valkey/valkey
#
# Run:
#   export BW_SESSION=$(bw unlock --raw)
#   bin/e2e spec/e2e/spreadsheet_sync_worker_e2e_spec.rb

RSpec.describe SpreadsheetSyncWorker, :e2e do
  before(:all) do
    WebMock.allow_net_connect!

    reports_url = Settings.sqs_reports_queue_url
    sqs_opts = { region: ENV.fetch("AWS_DEFAULT_REGION", "us-east-1") }
    if reports_url.start_with?("http://localhost")
      sqs_opts[:endpoint]    = "http://localhost:4566"
      sqs_opts[:credentials] = Aws::Credentials.new("test", "test")
    end
    setup_sqs = Aws::SQS::Client.new(**sqs_opts)

    setup_sqs.create_queue(
      queue_name: reports_url.split("/").last,
      attributes: { "FifoQueue" => "true", "ContentBasedDeduplication" => "false" }
    )
  end

  after(:all) { WebMock.disable_net_connect! }

  let(:access_token)   { fetch_google_access_token }
  let(:user_id)        { Digest::SHA256.hexdigest(access_token) }
  let(:spreadsheet_id) { ENV.fetch("GOOGLE_TEST_SPREADSHEET_ID") }
  let(:reports_url)    { Settings.sqs_reports_queue_url }

  let(:sqs) do
    options = { region: ENV.fetch("AWS_DEFAULT_REGION", "us-east-1") }
    if reports_url.start_with?("http://localhost")
      options[:endpoint]    = "http://localhost:4566"
      options[:credentials] = Aws::Credentials.new("test", "test")
    end
    Aws::SQS::Client.new(**options)
  end

  let(:test_record) do
    DamageReportRecord.new(
      name:          "e2e test portal",
      latitude:      "35.681236",
      longitude:     "139.767125",
      owned:         false,
      internal_date: 1700000000000
    )
  end

  before do
    sqs.purge_queue(queue_url: reports_url)
    UserStore.access_token.store(user_id, access_token)
    UserStore.spreadsheet_id.store(user_id, spreadsheet_id)
    allow(described_class).to receive(:perform_in)

    SqsClient.new(reports_url).send_messages(
      [test_record.to_h],
      attributes: { UserStore::USER_ID_ATTR => user_id }
    )
  end

  describe "#perform" do
    context "when reports queue has messages" do
      it "consumes all messages and appends rows to Google Sheets" do
        described_class.new.perform

        remaining = sqs.receive_message(
          queue_url: reports_url,
          max_number_of_messages: 1,
          wait_time_seconds: 1
        ).messages

        expect(remaining).to be_empty
      end
    end

    context "when reports queue is empty" do
      before { sqs.purge_queue(queue_url: reports_url) }

      it "does not raise an error" do
        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end
end
