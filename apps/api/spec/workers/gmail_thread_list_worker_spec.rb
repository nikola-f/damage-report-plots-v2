# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListWorker do
  let(:access_token) { "ya29.test_token" }
  let(:sqs_client)   { instance_double(SqsClient, send_messages: nil) }

  before do
    allow(ENV).to receive(:fetch).with("SQS_REPORT_QUEUE_URL").and_return("https://sqs.test/queue")
    allow(SqsClient).to receive(:new).with("https://sqs.test/queue").and_return(sqs_client)
  end

  describe "#perform" do
    let(:thread_ids) { %w[t1 t2] }
    let(:fetcher)    { instance_double(GmailThreadListFetcher, call: thread_ids) }

    before do
      allow(GmailThreadListFetcher).to receive(:new).and_return(fetcher)
    end

    it "instantiates GmailThreadListFetcher with the correct arguments" do
      described_class.new.perform(access_token)

      expect(GmailThreadListFetcher).to have_received(:new).with(access_token:)
    end

    it "calls GmailThreadListFetcher#call with q: nil by default" do
      described_class.new.perform(access_token)
      expect(fetcher).to have_received(:call).with(q: nil)
    end

    it "passes q to GmailThreadListFetcher#call when provided" do
      described_class.new.perform(access_token, "subject:damage report")
      expect(fetcher).to have_received(:call).with(q: "subject:damage report")
    end

    it "sends ReportTasks built from thread IDs to SQS" do
      described_class.new.perform(access_token)

      expect(sqs_client).to have_received(:send_messages).with(
        [ReportTask.new(thread_id: "t1"), ReportTask.new(thread_id: "t2")]
      )
    end

    context "when there are no thread IDs" do
      let(:fetcher) { instance_double(GmailThreadListFetcher, call: []) }

      it "does not call send_messages" do
        described_class.new.perform(access_token)
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
