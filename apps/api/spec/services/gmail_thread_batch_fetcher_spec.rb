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
      let(:all_ids)      { (1..(described_class::BATCH_SIZE + 5)).map { |i| "t#{i}" } }
      let(:first_batch)  { all_ids[0..(described_class::BATCH_SIZE - 1)] }
      let(:second_batch) { all_ids[described_class::BATCH_SIZE..] }

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
        expect(result.length).to eq(described_class::BATCH_SIZE + 5)
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

    context "when called with a block (streaming mode)" do
      context "when thread_ids is empty" do
        it "does not call batch_get_threads and does not yield" do
          allow(gmail_client).to receive(:batch_get_threads)
          yielded = []
          fetcher.call([]) { |m| yielded << m }
          expect(gmail_client).not_to have_received(:batch_get_threads)
          expect(yielded).to be_empty
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

        it "yields each GmailMessage" do
          yielded = []
          fetcher.call(thread_ids) { |m| yielded << m }
          expect(yielded).to all(be_a(GmailMessage))
          expect(yielded.map(&:id)).to eq(%w[m1 m2])
        end

        it "returns nil" do
          result = fetcher.call(thread_ids) { |m| m }
          expect(result).to be_nil
        end
      end

      context "when thread_ids exceeds BATCH_SIZE" do
        let(:all_ids)      { (1..(described_class::BATCH_SIZE + 5)).map { |i| "t#{i}" } }
        let(:first_batch)  { all_ids[0..(described_class::BATCH_SIZE - 1)] }
        let(:second_batch) { all_ids[described_class::BATCH_SIZE..] }

        def raw_threads_for(ids)
          ids.map { |id| { "id" => id, "messages" => [{ "id" => "m_#{id}", "internalDate" => "0", "payload" => {} }] } }
        end

        before do
          allow(gmail_client).to receive(:batch_get_threads).with(first_batch).and_return(raw_threads_for(first_batch))
          allow(gmail_client).to receive(:batch_get_threads).with(second_batch).and_return(raw_threads_for(second_batch))
        end

        it "yields all messages from all batches in order" do
          yielded = []
          fetcher.call(all_ids) { |m| yielded << m }
          expect(yielded.length).to eq(described_class::BATCH_SIZE + 5)
          expect(yielded.map(&:id)).to eq(all_ids.map { |id| "m_#{id}" })
        end

        it "calls batch_get_threads per slice, not all at once" do
          fetcher.call(all_ids) { |m| m }
          expect(gmail_client).to have_received(:batch_get_threads).twice
        end
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

    context "when batch_get_threads raises 429 on the first attempt" do
      let(:raw_thread) { { "id" => "t1", "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }] } }

      before do
        allow(fetcher).to receive(:sleep)
        responses = [
          -> { raise GmailClient::ApiError, "Gmail API error: 429 (batch part 0)" },
          -> { [raw_thread] }
        ]
        allow(gmail_client).to receive(:batch_get_threads) { responses.shift.call }
      end

      it "sleeps 2^0 seconds before retrying" do
        fetcher.call(%w[t1])
        expect(fetcher).to have_received(:sleep).with(1)
      end

      it "returns results after the successful retry" do
        result = fetcher.call(%w[t1])
        expect(result).not_to be_empty
      end
    end

    context "when 429 persists beyond MAX_RETRIES" do
      before do
        allow(fetcher).to receive(:sleep)
        allow(gmail_client).to receive(:batch_get_threads)
          .and_raise(GmailClient::ApiError, "Gmail API error: 429 (batch part 0)")
      end

      it "re-raises after MAX_RETRIES attempts" do
        expect { fetcher.call(%w[t1]) }.to raise_error(GmailClient::ApiError, /429/)
        expect(fetcher).to have_received(:sleep).exactly(GmailThreadBatchFetcher::MAX_RETRIES).times
      end
    end

    context "when 429 is raised 6 consecutive times before succeeding" do
      let(:raw_thread) { { "id" => "t1", "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }] } }

      before do
        allow(fetcher).to receive(:sleep)
        call_count = 0
        allow(gmail_client).to receive(:batch_get_threads) do
          call_count += 1
          raise GmailClient::ApiError, "Gmail API error: 429 (batch part 0)" if call_count <= 6
          [raw_thread]
        end
      end

      it "caps sleep at MAX_BACKOFF" do
        fetcher.call(%w[t1])
        expect(fetcher).to have_received(:sleep).with(GmailThreadBatchFetcher::MAX_BACKOFF).at_least(:once)
        expect(fetcher).not_to have_received(:sleep).with(be > GmailThreadBatchFetcher::MAX_BACKOFF)
      end
    end

    context "when 429 affects only one slice of a multi-batch call" do
      let(:all_ids)      { (1..(described_class::BATCH_SIZE + 5)).map { |i| "t#{i}" } }
      let(:first_batch)  { all_ids[0..(described_class::BATCH_SIZE - 1)] }
      let(:second_batch) { all_ids[described_class::BATCH_SIZE..] }

      def raw_threads_for(ids)
        ids.map { |id| { "id" => id, "messages" => [{ "id" => "m_#{id}", "internalDate" => "0", "payload" => {} }] } }
      end

      before do
        allow(fetcher).to receive(:sleep)
        second_batch_calls = 0
        allow(gmail_client).to receive(:batch_get_threads).with(first_batch)
          .and_return(raw_threads_for(first_batch))
        allow(gmail_client).to receive(:batch_get_threads).with(second_batch) do
          second_batch_calls += 1
          raise GmailClient::ApiError, "Gmail API error: 429 (batch part 0)" if second_batch_calls == 1
          raw_threads_for(second_batch)
        end
      end

      it "retries only the failing slice without repeating the first slice" do
        fetcher.call(all_ids)
        expect(gmail_client).to have_received(:batch_get_threads).with(first_batch).once
        expect(gmail_client).to have_received(:batch_get_threads).with(second_batch).twice
      end
    end

    context "when 403 userRateLimitExceeded is raised" do
      let(:raw_thread) { { "id" => "t1", "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }] } }

      before do
        allow(fetcher).to receive(:sleep)
        responses = [
          -> { raise GmailClient::ApiError, "Gmail API error: 403 User Rate Limit Exceeded (batch part 0)" },
          -> { [raw_thread] }
        ]
        allow(gmail_client).to receive(:batch_get_threads) { responses.shift.call }
      end

      it "retries and returns results" do
        result = fetcher.call(%w[t1])
        expect(result).not_to be_empty
      end

      it "sleeps before retrying" do
        fetcher.call(%w[t1])
        expect(fetcher).to have_received(:sleep).with(1)
      end
    end

    context "when 403 Quota exceeded (per-user QPM limit) is raised" do
      let(:quota_error) { "Gmail API error: 403 Quota exceeded for quota metric 'Queries' and limit 'Queries per minute per user' of service 'gmail.googleapis.com' (batch part 0)" }
      let(:raw_thread) { { "id" => "t1", "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }] } }

      before do
        allow(fetcher).to receive(:sleep)
        responses = [
          -> { raise GmailClient::ApiError, quota_error },
          -> { [raw_thread] }
        ]
        allow(gmail_client).to receive(:batch_get_threads) { responses.shift.call }
      end

      it "retries and returns results" do
        result = fetcher.call(%w[t1])
        expect(result).not_to be_empty
      end

      it "sleeps before retrying" do
        fetcher.call(%w[t1])
        expect(fetcher).to have_received(:sleep).with(1)
      end
    end

    context "when 403 insufficientPermissions is raised" do
      before do
        allow(gmail_client).to receive(:batch_get_threads)
          .and_raise(GmailClient::ApiError, "Gmail API error: 403 Insufficient Permission (batch part 0)")
      end

      it "re-raises immediately without retrying" do
        expect { fetcher.call(%w[t1]) }
          .to raise_error(GmailClient::ApiError, /Insufficient Permission/)
      end
    end

    context "when 503 Service Unavailable is raised" do
      let(:raw_thread) { { "id" => "t1", "messages" => [{ "id" => "m1", "internalDate" => "1000", "payload" => {} }] } }

      before do
        allow(fetcher).to receive(:sleep)
        responses = [
          -> { raise GmailClient::ApiError, "Gmail API error: 503 The service is currently unavailable. (batch part 5)" },
          -> { [raw_thread] }
        ]
        allow(gmail_client).to receive(:batch_get_threads) { responses.shift.call }
      end

      it "retries and returns results" do
        result = fetcher.call(%w[t1])
        expect(result).not_to be_empty
      end

      it "sleeps before retrying" do
        fetcher.call(%w[t1])
        expect(fetcher).to have_received(:sleep).with(1)
      end
    end
  end
end
