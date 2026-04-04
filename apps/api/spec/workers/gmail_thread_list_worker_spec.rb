# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListWorker do
  let(:user_id)      { "user_001" }
  let(:email)        { "user@example.com" }
  let(:access_token) { "ya29.test_token" }

  let(:sqs_client) { instance_double(SqsClient, send_messages: nil) }

  before do
    allow(ENV).to receive(:fetch).with("SQS_REPORT_QUEUE_URL").and_return("https://sqs.test/queue")
    allow(SqsClient).to receive(:new).with("https://sqs.test/queue").and_return(sqs_client)
  end

  describe "#perform" do
    let(:tasks) do
      [
        ReportTask.new(thread_id: "t1", user_id:, email:),
        ReportTask.new(thread_id: "t2", user_id:, email:)
      ]
    end
    let(:fetcher) { instance_double(GmailThreadListFetcher, call: tasks) }

    before do
      allow(GmailThreadListFetcher).to receive(:new).and_return(fetcher)
    end

    it "instantiates GmailThreadListFetcher with the correct arguments" do
      described_class.new.perform(user_id, email, access_token)

      expect(GmailThreadListFetcher).to have_received(:new).with(
        access_token:,
        user_id:,
        email:
      )
    end

    it "calls GmailThreadListFetcher#call with q: nil by default" do
      described_class.new.perform(user_id, email, access_token)
      expect(fetcher).to have_received(:call).with(q: nil)
    end

    it "passes q to GmailThreadListFetcher#call when provided" do
      described_class.new.perform(user_id, email, access_token, "subject:damage report")
      expect(fetcher).to have_received(:call).with(q: "subject:damage report")
    end

    it "sends the tasks to SQS" do
      described_class.new.perform(user_id, email, access_token)
      expect(sqs_client).to have_received(:send_messages).with(tasks)
    end

    context "when there are no tasks" do
      let(:fetcher) { instance_double(GmailThreadListFetcher, call: []) }

      it "does not call send_messages" do
        described_class.new.perform(user_id, email, access_token)
        expect(sqs_client).not_to have_received(:send_messages)
      end
    end
  end

  describe "Sidekiq options" do
    it "retries up to 3 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end
