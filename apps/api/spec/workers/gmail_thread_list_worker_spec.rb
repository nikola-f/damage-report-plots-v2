# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListWorker do
  let(:access_token) { "ya29.test_token" }
  let(:sqs_client)   { instance_double(SqsClient, send_messages: nil) }
  let(:thread_ids)   { %w[t1 t2] }
  let(:fetcher)      { instance_double(GmailThreadListFetcher, call: thread_ids) }

  before do
    allow(ENV).to receive(:fetch).with("SQS_REPORT_QUEUE_URL").and_return("https://sqs.test/queue")
    allow(SqsClient).to receive(:new).with("https://sqs.test/queue").and_return(sqs_client)
    allow(GmailThreadListFetcher).to receive(:new).and_return(fetcher)
  end

  describe "#perform" do
    it "builds the query with fixed subject, from, smaller, and date range" do
      described_class.new.perform(access_token, "2024-01-01")
      expect(fetcher).to have_received(:call).with(
        q: "subject:Ingress Damage Report: Entities attacked by " \
           "after:2024/01/01 before:2025/01/01 " \
           "{from:ingress-support@google.com from:ingress-support@nianticlabs.com " \
           "from:ingress-support@nianticspatial.com} " \
           "smaller:200K"
      )
    end

    it "handles leap year correctly (2024-02-29 + 1 year = 2025-02-28)" do
      described_class.new.perform(access_token, "2024-02-29")
      expect(fetcher).to have_received(:call).with(
        q: "subject:Ingress Damage Report: Entities attacked by " \
           "after:2024/02/29 before:2025/02/28 " \
           "{from:ingress-support@google.com from:ingress-support@nianticlabs.com " \
           "from:ingress-support@nianticspatial.com} " \
           "smaller:200K"
      )
    end

    it "defaults after_date to 2012-10-15 when nil" do
      described_class.new.perform(access_token, nil)
      expect(fetcher).to have_received(:call).with(
        q: "subject:Ingress Damage Report: Entities attacked by " \
           "after:2012/10/15 before:2013/10/15 " \
           "{from:ingress-support@google.com from:ingress-support@nianticlabs.com " \
           "from:ingress-support@nianticspatial.com} " \
           "smaller:200K"
      )
    end

    it "sends ReportTasks built from thread IDs to SQS" do
      described_class.new.perform(access_token, "2024-01-01")
      expect(sqs_client).to have_received(:send_messages).with(
        [ReportTask.new(thread_id: "t1"), ReportTask.new(thread_id: "t2")]
      )
    end

    context "when there are no thread IDs" do
      let(:fetcher) { instance_double(GmailThreadListFetcher, call: []) }

      it "does not call send_messages" do
        described_class.new.perform(access_token, "2024-01-01")
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
