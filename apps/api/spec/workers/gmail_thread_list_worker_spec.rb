# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListWorker do
  let(:user_id)             { "12345678901234567" }
  let(:access_token)        { "ya29.test_token" }
  let(:token_store)         { instance_double(UserStore, fetch: access_token) }
  let(:threads_found_store) { instance_double(UserStore, store: nil) }
  let(:sqs_client)          { instance_double(SqsClient, send_messages: nil) }
  let(:fetcher)             { instance_double(GmailThreadListFetcher) }

  # Fix Time.now so the loop covers exactly one 30-day window
  let(:fixed_now) { Time.at(DamageReportQuery::DEFAULT_AFTER_DATE) }
  let(:after_date) { DamageReportQuery::DEFAULT_AFTER_DATE }

  before do
    allow(UserStore).to receive(:access_token).and_return(token_store)
    allow(UserStore).to receive(:threads_found).and_return(threads_found_store)
    allow(SqsClient).to receive(:new).with(Settings.sqs_thread_ids_queue_url).and_return(sqs_client)
    allow(GmailThreadListFetcher).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:call).and_return(%w[t1 t2])
    allow(Time).to receive(:now).and_return(fixed_now)
  end

  describe "#perform" do
    it "fetches the access token using user_id" do
      described_class.new.perform(user_id, after_date)

      expect(token_store).to have_received(:fetch).with(user_id)
    end

    it "calls GmailThreadListFetcher with a 30-day window query" do
      before_epoch = after_date + DamageReportQuery::DAYS_WINDOW * 24 * 3_600
      described_class.new.perform(user_id, after_date)

      expect(fetcher).to have_received(:call).with(
        q: DamageReportQuery.new(after_date:, before_date: before_epoch).to_s
      )
    end

    it "stores the total thread count in threads_found" do
      described_class.new.perform(user_id, after_date)

      expect(threads_found_store).to have_received(:store).with(user_id, "2")
    end

    it "sends thread IDs sorted ascending to SQS with user_id as attribute" do
      allow(fetcher).to receive(:call).and_return(%w[t3 t1 t2])
      described_class.new.perform(user_id, after_date)

      expect(sqs_client).to have_received(:send_messages)
        .with(%w[t1 t2 t3], attributes: { UserStore::USER_ID_ATTR => user_id })
    end

    context "when after_date is nil, starts from DEFAULT_AFTER_DATE" do
      it "uses DEFAULT_AFTER_DATE as the first window start" do
        before_epoch = DamageReportQuery::DEFAULT_AFTER_DATE + DamageReportQuery::DAYS_WINDOW * 24 * 3_600
        described_class.new.perform(user_id, nil)

        expect(fetcher).to have_received(:call).with(
          q: DamageReportQuery.new(after_date: DamageReportQuery::DEFAULT_AFTER_DATE, before_date: before_epoch).to_s
        )
      end
    end

    context "when window thread_ids exceed threads_per_message" do
      let(:thread_ids) { (1..(Settings.thread_list_worker_threads_per_message + 1)).map { |i| "t#{i}" } }

      before { allow(fetcher).to receive(:call).and_return(thread_ids) }

      it "slices and calls send_messages twice for a single window" do
        described_class.new.perform(user_id, after_date)

        expect(sqs_client).to have_received(:send_messages).twice
      end
    end

    context "when windows span multiple 30-day periods" do
      # Set Time.now to DEFAULT + 31 days so two windows are iterated
      let(:fixed_now) { Time.at(DamageReportQuery::DEFAULT_AFTER_DATE + 31 * 24 * 3_600) }

      before { allow(fetcher).to receive(:call).and_return(%w[t2 t1], %w[t4 t3]) }

      it "calls fetcher for each 30-day window" do
        described_class.new.perform(user_id, after_date)

        expect(fetcher).to have_received(:call).twice
      end

      it "stores the accumulated total in threads_found" do
        described_class.new.perform(user_id, after_date)

        expect(threads_found_store).to have_received(:store).with(user_id, "4")
      end

      it "sends each window's IDs sorted ascending in separate SQS calls" do
        described_class.new.perform(user_id, after_date)

        expect(sqs_client).to have_received(:send_messages)
          .with(%w[t1 t2], attributes: { UserStore::USER_ID_ATTR => user_id })
        expect(sqs_client).to have_received(:send_messages)
          .with(%w[t3 t4], attributes: { UserStore::USER_ID_ATTR => user_id })
      end
    end

    context "when total thread_ids exceed 3000 across windows" do
      # Allow 3 windows but expect break after 2 (2000 + 2000 > 3000)
      let(:fixed_now) { Time.at(DamageReportQuery::DEFAULT_AFTER_DATE + 61 * 24 * 3_600) }
      let(:window_ids) { (1..2000).map { |i| "t#{i}" } }

      before { allow(fetcher).to receive(:call).and_return(window_ids) }

      it "stops fetching after total exceeds 3000" do
        described_class.new.perform(user_id, after_date)

        expect(fetcher).to have_received(:call).twice
      end

      it "stores the actual total (may exceed 3000)" do
        described_class.new.perform(user_id, after_date)

        expect(threads_found_store).to have_received(:store).with(user_id, "4000")
      end
    end

    context "when there are no thread IDs in any window" do
      before { allow(fetcher).to receive(:call).and_return([]) }

      it "stores 0 in threads_found" do
        described_class.new.perform(user_id, after_date)

        expect(threads_found_store).to have_received(:store).with(user_id, "0")
      end

      it "does not call send_messages" do
        described_class.new.perform(user_id, after_date)

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
