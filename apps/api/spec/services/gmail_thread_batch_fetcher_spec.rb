# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadBatchFetcher do
  let(:access_token) { "ya29.test_token" }
  let(:gmail_client) { instance_double(GmailClient) }

  let(:fetcher) do
    described_class.new(access_token:, gmail_client:)
  end

  describe "#call" do
    context "when thread_ids is empty" do
      before do
        allow(gmail_client).to receive(:batch_get_threads)
      end

      it "returns an empty array without calling batch_get_threads" do
        result = fetcher.call([])
        expect(result).to eq([])
        expect(gmail_client).not_to have_received(:batch_get_threads)
      end
    end

    context "when thread_ids fits within a single batch" do
      let(:thread_ids) { %w[t1 t2 t3] }
      let(:threads)    { thread_ids.map { |id| { "id" => id, "messages" => [] } } }

      before do
        allow(gmail_client).to receive(:batch_get_threads).with(thread_ids).and_return(threads)
      end

      it "returns the fetched threads" do
        expect(fetcher.call(thread_ids)).to eq(threads)
      end

      it "calls batch_get_threads once" do
        fetcher.call(thread_ids)
        expect(gmail_client).to have_received(:batch_get_threads).once
      end
    end

    context "when thread_ids exceeds BATCH_SIZE" do
      let(:all_ids) { (1..150).map { |i| "t#{i}" } }
      let(:first_batch)  { all_ids[0..99] }
      let(:second_batch) { all_ids[100..149] }
      let(:first_threads)  { first_batch.map  { |id| { "id" => id, "messages" => [] } } }
      let(:second_threads) { second_batch.map { |id| { "id" => id, "messages" => [] } } }

      before do
        allow(gmail_client).to receive(:batch_get_threads).with(first_batch).and_return(first_threads)
        allow(gmail_client).to receive(:batch_get_threads).with(second_batch).and_return(second_threads)
      end

      it "calls batch_get_threads twice" do
        fetcher.call(all_ids)
        expect(gmail_client).to have_received(:batch_get_threads).twice
      end

      it "returns all threads concatenated in order" do
        result = fetcher.call(all_ids)
        expect(result.length).to eq(150)
        expect(result.map { |t| t["id"] }).to eq(all_ids)
      end
    end

    context "when messages have multiple parts with different mimeTypes" do
      let(:html_part)  { { "mimeType" => "text/html",  "body" => { "data" => "html_data" } } }
      let(:plain_part) { { "mimeType" => "text/plain", "body" => { "data" => "plain_data" } } }

      let(:raw_thread) do
        {
          "id" => "t1",
          "messages" => [
            { "id" => "m1", "internalDate" => "1000",
              "payload" => { "parts" => [plain_part, html_part] } }
          ]
        }
      end

      before { allow(gmail_client).to receive(:batch_get_threads).and_return([raw_thread]) }

      it "keeps only text/html parts" do
        result = fetcher.call(["t1"])
        parts = result.first.dig("messages", 0, "payload", "parts")
        expect(parts).to eq([html_part])
      end
    end

    context "when messages have no parts" do
      let(:raw_thread) do
        {
          "id" => "t1",
          "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }]
        }
      end

      before { allow(gmail_client).to receive(:batch_get_threads).and_return([raw_thread]) }

      it "returns the message with an empty parts array" do
        result = fetcher.call(["t1"])
        parts = result.first.dig("messages", 0, "payload", "parts")
        expect(parts).to eq([])
      end
    end

    context "when GmailClient raises QuotaExceededError" do
      before do
        allow(gmail_client).to receive(:batch_get_threads)
          .and_raise(GmailClient::QuotaExceededError, "quota exceeded")
      end

      it "propagates the error (for Sidekiq retry)" do
        expect { fetcher.call(%w[t1]) }
          .to raise_error(GmailClient::QuotaExceededError, "quota exceeded")
      end
    end

    context "when GmailClient raises ApiError" do
      before do
        allow(gmail_client).to receive(:batch_get_threads)
          .and_raise(GmailClient::ApiError, "401 Unauthorized")
      end

      it "propagates the error" do
        expect { fetcher.call(%w[t1]) }
          .to raise_error(GmailClient::ApiError, "401 Unauthorized")
      end
    end
  end
end
