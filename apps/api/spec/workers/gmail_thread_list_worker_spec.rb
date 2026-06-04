# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadListWorker do
  let(:user_id)             { "12345678901234567" }
  let(:access_token)        { "ya29.test_token" }
  let(:token_store)         { instance_double(UserStore, fetch: access_token) }
  let(:threads_found_store) { instance_double(UserStore, store: nil) }
  let(:sqs_client)          { instance_double(SqsClient, send_messages: nil) }
  let(:thread_ids)          { %w[t1 t2] }
  let(:fetcher) { instance_double(GmailThreadListFetcher) }

  before do
    allow(UserStore).to receive(:access_token).and_return(token_store)
    allow(UserStore).to receive(:threads_found).and_return(threads_found_store)
    allow(SqsClient).to receive(:new).with(Settings.sqs_thread_ids_queue_url).and_return(sqs_client)
    allow(GmailThreadListFetcher).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:call).and_return(thread_ids)
  end

  describe "#perform" do
    it "fetches the access token using user_id" do
      described_class.new.perform(user_id, "2024-01-01")

      expect(token_store).to have_received(:fetch).with(user_id)
    end

    it "calls GmailThreadListFetcher with the Ingress damage report query" do
      described_class.new.perform(user_id, "2024-01-01")

      expect(fetcher).to have_received(:call).with(
        q: IngressDamageReportQuery.new(after_date: "2024-01-01").to_s
      )
    end

    it "stores the thread count in threads_found" do
      described_class.new.perform(user_id, "2024-01-01")

      expect(threads_found_store).to have_received(:store).with(user_id, thread_ids.size.to_s)
    end

    it "sends thread IDs to SQS with user_id as attribute" do
      described_class.new.perform(user_id, "2024-01-01")

      expect(sqs_client).to have_received(:send_messages)
        .with(%w[t1 t2], attributes: { UserStore::USER_ID_ATTR => user_id })
    end

    context "when thread_ids exceed threads_per_message" do
      let(:thread_ids) { (1..(Settings.thread_list_worker_threads_per_message + 1)).map { |i| "t#{i}" } }

      it "calls send_messages once per slice" do
        described_class.new.perform(user_id, "2024-01-01")

        expect(sqs_client).to have_received(:send_messages).twice
      end

      it "sends the first slice of threads_per_message items" do
        described_class.new.perform(user_id, "2024-01-01")

        expect(sqs_client).to have_received(:send_messages)
          .with(thread_ids[0..(Settings.thread_list_worker_threads_per_message - 1)],
                attributes: { UserStore::USER_ID_ATTR => user_id })
      end

      it "sends the remainder in a second slice" do
        described_class.new.perform(user_id, "2024-01-01")

        expect(sqs_client).to have_received(:send_messages)
          .with(thread_ids[Settings.thread_list_worker_threads_per_message..],
                attributes: { UserStore::USER_ID_ATTR => user_id })
      end
    end

    context "when there are no thread IDs" do
      before { allow(fetcher).to receive(:call).and_return([]) }

      it "stores 0 in threads_found" do
        described_class.new.perform(user_id, "2024-01-01")

        expect(threads_found_store).to have_received(:store).with(user_id, "0")
      end

      it "does not call send_messages" do
        described_class.new.perform(user_id, "2024-01-01")

        expect(sqs_client).not_to have_received(:send_messages)
      end
    end

    context "when no threads found on the first window and default after_date is used" do
      let(:second_epoch) do
        next_date = Time.at(IngressDamageReportQuery::DEFAULT_AFTER_DATE).utc.to_date >>
                    IngressDamageReportQuery::MONTHS_RANGE
        Time.utc(next_date.year, next_date.month, next_date.day).to_i
      end

      before do
        allow(fetcher).to receive(:call).and_return([], thread_ids)
      end

      it "retries with the next window" do
        described_class.new.perform(user_id, nil)

        expect(fetcher).to have_received(:call).with(
          q: IngressDamageReportQuery.new(after_date: second_epoch).to_s
        )
      end

      it "sends the threads found in the second window to SQS" do
        described_class.new.perform(user_id, nil)

        expect(sqs_client).to have_received(:send_messages)
          .with(%w[t1 t2], attributes: { UserStore::USER_ID_ATTR => user_id })
      end

      it "stores the count from the second window in threads_found" do
        described_class.new.perform(user_id, nil)

        expect(threads_found_store).to have_received(:store).with(user_id, thread_ids.size.to_s)
      end
    end

    context "when all windows up to today are exhausted with default after_date" do
      before do
        allow(fetcher).to receive(:call).and_return([])
        allow(Date).to receive(:today).and_return(
          Time.at(IngressDamageReportQuery::DEFAULT_AFTER_DATE).utc.to_date
        )
      end

      it "does not call send_messages" do
        described_class.new.perform(user_id, nil)

        expect(sqs_client).not_to have_received(:send_messages)
      end

      it "stores 0 in threads_found" do
        described_class.new.perform(user_id, nil)

        expect(threads_found_store).to have_received(:store).with(user_id, "0")
      end
    end
  end

  describe "Sidekiq options" do
    it "retries up to 3 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end
