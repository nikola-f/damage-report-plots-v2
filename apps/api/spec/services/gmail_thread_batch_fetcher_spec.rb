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
      let(:thread_ids) { %w[t1 t2] }
      let(:raw_threads) do
        [
          { "id" => "t1", "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }] },
          { "id" => "t2", "messages" => [{ "id" => "m2", "internalDate" => "2000", "payload" => {} }] }
        ]
      end

      before do
        allow(gmail_client).to receive(:batch_get_threads).with(thread_ids).and_return(raw_threads)
      end

      it "returns GmailMessage objects" do
        expect(fetcher.call(thread_ids)).to all(be_a(GmailMessage))
      end

      it "returns messages from all threads flattened in order" do
        result = fetcher.call(thread_ids)
        expect(result.map(&:id)).to eq(%w[m1 m2])
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

      def raw_threads_for(ids)
        ids.map { |id| { "id" => id, "messages" => [{ "id" => "m_#{id}", "internalDate" => "0", "payload" => {} }] } }
      end

      before do
        allow(gmail_client).to receive(:batch_get_threads).with(first_batch).and_return(raw_threads_for(first_batch))
        allow(gmail_client).to receive(:batch_get_threads).with(second_batch).and_return(raw_threads_for(second_batch))
      end

      it "calls batch_get_threads twice" do
        fetcher.call(all_ids)
        expect(gmail_client).to have_received(:batch_get_threads).twice
      end

      it "returns all messages concatenated in order" do
        result = fetcher.call(all_ids)
        expect(result.length).to eq(150)
        expect(result.map(&:id)).to eq(all_ids.map { |id| "m_#{id}" })
      end
    end

    context "when batch_get_threads returns nil for some entries" do
      let(:thread_ids) { %w[t1 t2 t3] }

      before do
        allow(gmail_client).to receive(:batch_get_threads).and_return([
          { "id" => "t1", "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }] },
          nil,
          { "id" => "t3", "messages" => [{ "id" => "m3", "internalDate" => "3000", "payload" => {} }] }
        ])
      end

      it "skips nil entries and returns messages from non-nil threads" do
        result = fetcher.call(thread_ids)
        expect(result.map(&:id)).to eq(%w[m1 m3])
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
