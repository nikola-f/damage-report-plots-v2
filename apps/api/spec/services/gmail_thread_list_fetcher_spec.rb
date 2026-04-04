# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListFetcher do
  let(:access_token) { "ya29.test_token" }
  let(:user_id)      { "user_001" }
  let(:email)        { "user@example.com" }

  let(:gmail_client) { instance_double(GmailClient) }
  let(:sqs_client)   { instance_double(SqsClient) }

  let(:fetcher) do
    described_class.new(
      access_token:,
      user_id:,
      email:,
      gmail_client:,
      sqs_client:
    )
  end

  describe "#call" do
    context "when there is a single page of results" do
      let(:threads_response) do
        {
          "threads"           => [{ "id" => "t1" }, { "id" => "t2" }],
          "resultSizeEstimate" => 2
        }
      end

      before do
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: nil).and_return(threads_response)
        allow(sqs_client).to receive(:send_messages)
      end

      it "calls send_messages with ReportTask objects for each thread" do
        fetcher.call

        expect(sqs_client).to have_received(:send_messages).with(
          [
            ReportTask.new(thread_id: "t1", user_id:, email:),
            ReportTask.new(thread_id: "t2", user_id:, email:)
          ]
        )
      end

      it "fetches only one page" do
        fetcher.call
        expect(gmail_client).to have_received(:list_threads).once
      end
    end

    context "when there are multiple pages" do
      let(:page1_response) do
        {
          "threads"       => [{ "id" => "t1" }, { "id" => "t2" }],
          "nextPageToken" => "token_page2"
        }
      end
      let(:page2_response) do
        {
          "threads"           => [{ "id" => "t3" }],
          "resultSizeEstimate" => 3
        }
      end

      before do
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: nil).and_return(page1_response)
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: "token_page2").and_return(page2_response)
        allow(sqs_client).to receive(:send_messages)
      end

      it "fetches all pages and enqueues all threads" do
        fetcher.call

        expect(sqs_client).to have_received(:send_messages).with(
          [
            ReportTask.new(thread_id: "t1", user_id:, email:),
            ReportTask.new(thread_id: "t2", user_id:, email:),
            ReportTask.new(thread_id: "t3", user_id:, email:)
          ]
        )
      end

      it "fetches exactly two pages" do
        fetcher.call
        expect(gmail_client).to have_received(:list_threads).twice
      end
    end

    context "when the q parameter is given" do
      let(:query) { "subject:damage report" }
      let(:threads_response) { { "threads" => [{ "id" => "t1" }] } }

      before do
        allow(gmail_client).to receive(:list_threads).with(q: query, page_token: nil).and_return(threads_response)
        allow(sqs_client).to receive(:send_messages)
      end

      it "passes q to GmailClient#list_threads" do
        fetcher.call(q: query)
        expect(gmail_client).to have_received(:list_threads).with(q: query, page_token: nil)
      end
    end

    context "when there are no threads" do
      let(:empty_response) { { "resultSizeEstimate" => 0 } }

      before do
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: nil).and_return(empty_response)
        allow(sqs_client).to receive(:send_messages)
      end

      it "returns an empty array without calling send_messages" do
        result = fetcher.call
        expect(result).to eq([])
        expect(sqs_client).not_to have_received(:send_messages)
      end
    end

    context "when GmailClient raises QuotaExceededError" do
      before do
        allow(gmail_client).to receive(:list_threads).and_raise(GmailClient::QuotaExceededError, "quota exceeded")
      end

      it "propagates the error (for Sidekiq retry)" do
        expect { fetcher.call }.to raise_error(GmailClient::QuotaExceededError, "quota exceeded")
      end
    end

    context "when GmailClient raises ApiError" do
      before do
        allow(gmail_client).to receive(:list_threads).and_raise(GmailClient::ApiError, "401 Unauthorized")
      end

      it "propagates the error" do
        expect { fetcher.call }.to raise_error(GmailClient::ApiError, "401 Unauthorized")
      end
    end
  end
end
