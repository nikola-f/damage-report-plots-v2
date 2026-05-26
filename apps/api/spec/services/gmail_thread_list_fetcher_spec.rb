# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListFetcher do
  let(:access_token) { "ya29.test_token" }
  let(:gmail_client) { instance_double(GmailClient) }
  let(:fetcher)      { described_class.new(access_token:, gmail_client:) }

  describe "#call" do
    context "when there is a single page of results" do
      let(:threads_response) do
        {
          "threads" => [{ "id" => "t1" }, { "id" => "t2" }],
          "resultSizeEstimate" => 2
        }
      end

      before do
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: nil).and_return(threads_response)
      end

      it "returns thread IDs" do
        expect(fetcher.call).to eq(%w[t1 t2])
      end

      it "fetches only one page" do
        fetcher.call
        expect(gmail_client).to have_received(:list_threads).once
      end
    end

    context "when there are multiple pages" do
      let(:page1_response) do
        {
          "threads" => [{ "id" => "t1" }, { "id" => "t2" }],
          "nextPageToken" => "token_page2"
        }
      end
      let(:page2_response) do
        {
          "threads" => [{ "id" => "t3" }],
          "resultSizeEstimate" => 3
        }
      end

      before do
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: nil).and_return(page1_response)
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: "token_page2").and_return(page2_response)
      end

      it "returns thread IDs from all pages" do
        expect(fetcher.call).to eq(%w[t1 t2 t3])
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
      end

      it "returns an empty array" do
        expect(fetcher.call).to eq([])
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

    context "when threads exceed MAX_THREADS across pages" do
      let(:page1_threads) { (1..5000).map { |i| { "id" => "t#{i}" } } }
      let(:page1_response) do
        { "threads" => page1_threads, "nextPageToken" => "token_page2" }
      end
      let(:page2_response) do
        { "threads" => [{ "id" => "t5001" }], "resultSizeEstimate" => 5001 }
      end

      before do
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: nil).and_return(page1_response)
        allow(gmail_client).to receive(:list_threads).with(q: nil, page_token: "token_page2").and_return(page2_response)
      end

      it "returns exactly MAX_THREADS thread IDs" do
        expect(fetcher.call.size).to eq(described_class::MAX_THREADS)
      end

      it "does not fetch the next page after reaching the limit" do
        fetcher.call
        expect(gmail_client).to have_received(:list_threads).once
      end
    end
  end
end
