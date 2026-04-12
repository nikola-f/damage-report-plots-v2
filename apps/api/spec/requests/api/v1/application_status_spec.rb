# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/application_status", type: :request do
  let(:access_token_store) { instance_double(UserStore, store: nil) }
  let(:report_sqs)         { instance_double(SqsClient, queue_depth: { available: 3, in_flight: 1 }) }
  let(:portal_sqs)         { instance_double(SqsClient, queue_depth: { available: 0, in_flight: 2 }) }

  before do
    allow(UserStore).to receive(:access_token).and_return(access_token_store)
    allow(SqsClient).to receive(:new).with(Settings.sqs_thread_ids_queue_url).and_return(report_sqs)
    allow(SqsClient).to receive(:new).with(Settings.sqs_reports_queue_url).and_return(portal_sqs)
    allow(REDIS).to receive(:get).with("gmail_quota:project").and_return("5000")
    allow(REDIS).to receive(:ttl).with("gmail_quota:project").and_return(42)
  end

  context "with active session" do
    before { login_as }

    it "returns gmail quota usage" do
      get "/api/v1/application_status"

      quota = json_response["gmail_quota"]
      expect(quota["used"]).to eq(5000)
      expect(quota["limit"]).to eq(GmailClient::PER_PROJECT_LIMIT)
      expect(quota["remaining"]).to eq(GmailClient::PER_PROJECT_LIMIT - 5000)
      expect(quota["window_seconds"]).to eq(GmailClient::QUOTA_WINDOW)
      expect(quota["resets_in_seconds"]).to eq(42)
    end

    it "returns SQS queue depths" do
      get "/api/v1/application_status"

      queues = json_response["sqs_queues"]
      expect(queues["thread_ids"]).to eq("available" => 3, "in_flight" => 1)
      expect(queues["reports"]).to eq("available" => 0, "in_flight" => 2)
    end

    context "when no quota has been used yet (key absent)" do
      before do
        allow(REDIS).to receive(:get).with("gmail_quota:project").and_return(nil)
        allow(REDIS).to receive(:ttl).with("gmail_quota:project").and_return(-2)
      end

      it "reports zero usage and zero resets_in_seconds" do
        get "/api/v1/application_status"

        quota = json_response["gmail_quota"]
        expect(quota["used"]).to eq(0)
        expect(quota["remaining"]).to eq(GmailClient::PER_PROJECT_LIMIT)
        expect(quota["resets_in_seconds"]).to eq(0)
      end
    end
  end

  context "without session" do
    it "returns unauthorized" do
      get "/api/v1/application_status"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
