# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThreadBatchWorker do
  let(:user_id)            { "12345678901234567" }
  let(:access_token)       { "ya29.test_token" }
  let(:thread_ids)         { %w[t1 t2 t3] }
  let(:report_sqs_client)  { instance_double(SqsClient) }
  let(:portal_sqs_client)  { instance_double(SqsClient, send_messages: nil) }
  let(:token_store)        { instance_double(UserStore, fetch: access_token) }

  let(:portal)        { DamageReportRecord.new(name: "ハチ公", latitude: "35.0", longitude: "139.0", owned: false, internal_date: 16999200) }
  let(:decoder)       { instance_double(EmailHtmlDecoder) }
  let(:internal_date) { "1700000000000" }
  let(:gmail_message) { instance_double(GmailMessage, html_decoder: decoder, internal_date:) }
  let(:fetcher) do
    instance_double(GmailThreadBatchFetcher).tap do |f|
      allow(f).to receive(:call).and_yield(gmail_message)
    end
  end

  let(:message) do
    user_id_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: user_id)
    instance_double(
      Aws::SQS::Types::Message,
      body: JSON.generate(thread_ids),
      message_attributes: { UserStore::USER_ID_ATTR => user_id_attr },
      message_id: "msg-1",
      receipt_handle: "rh-1"
    )
  end

  # increment returns the new total (Redis INCRBY); default reaches threads_found
  # so the run counts as complete and last_processed_at is recorded.
  let(:threads_processed_store)          { instance_double(UserStore::CounterStore, increment: thread_ids.size) }
  let(:threads_found_store)              { instance_double(UserStore, fetch: thread_ids.size.to_s) }
  let(:portals_found_store)              { instance_double(UserStore::CounterStore, increment: nil) }
  let(:threads_max_internal_date_store)  { instance_double(UserStore, fetch: "0", store: nil) }
  let(:last_processed_at_store)          { instance_double(UserStore, fetch: "0", store: nil) }

  before do
    allow(REDIS).to receive(:set)
      .with(GmailThreadBatchWorker::LOCK_KEY, kind_of(String), nx: true, ex: Settings.thread_batch_worker_lock_ttl)
      .and_return("OK")
    allow(REDIS).to receive(:eval)
    allow(SqsClient).to receive(:new).with(Settings.sqs_reports_queue_url).and_return(portal_sqs_client)
    allow(SqsClient).to receive(:new).with(Settings.sqs_thread_ids_queue_url).and_return(report_sqs_client)
    allow(report_sqs_client).to receive(:receive_messages)
      .with(message_attribute_names: [UserStore::USER_ID_ATTR], max_messages: 1)
      .and_return([message], [])
    allow(report_sqs_client).to receive(:delete_messages)
    allow(UserStore).to receive(:access_token).and_return(token_store)
    allow(UserStore).to receive(:threads_processed).and_return(threads_processed_store)
    allow(UserStore).to receive(:threads_found).and_return(threads_found_store)
    allow(UserStore).to receive(:portals_found).and_return(portals_found_store)
    allow(UserStore).to receive(:threads_max_internal_date).and_return(threads_max_internal_date_store)
    allow(UserStore).to receive(:last_processed_at).and_return(last_processed_at_store)
    allow(GmailThreadBatchFetcher).to receive(:new).and_return(fetcher)
    allow(decoder).to receive(:extract_portals).with(internal_date:).and_return([portal])
    allow(described_class).to receive(:perform_in)
  end

  describe "#perform" do
    it "receives messages one at a time with user_id attribute" do
      described_class.new.perform

      expect(report_sqs_client).to have_received(:receive_messages)
        .with(message_attribute_names: [UserStore::USER_ID_ATTR], max_messages: 1)
        .at_least(:once)
    end

    it "fetches the access token using user_id" do
      described_class.new.perform

      expect(token_store).to have_received(:fetch).with(user_id)
    end

    it "calls GmailThreadBatchFetcher with access_token and thread_ids" do
      described_class.new.perform

      expect(GmailThreadBatchFetcher).to have_received(:new).with(access_token:)
      expect(fetcher).to have_received(:call).with(thread_ids)
    end

    it "sends DamageReportRecord hashes to the portal SQS queue with user_id attribute" do
      described_class.new.perform

      expect(portal_sqs_client).to have_received(:send_messages)
        .with([portal.to_h],
              attributes: { UserStore::USER_ID_ATTR => user_id })
    end

    it "deletes the thread_ids message after successfully processing it" do
      described_class.new.perform

      expect(report_sqs_client).to have_received(:delete_messages).with("rh-1")
    end

    it "increments threads_processed by the number of thread IDs in the message" do
      described_class.new.perform

      expect(threads_processed_store).to have_received(:increment).with(user_id, by: thread_ids.size)
    end

    it "stores the max internal_date before deleting the SQS message" do
      described_class.new.perform

      expect(threads_max_internal_date_store).to have_received(:store).with(user_id, internal_date)
    end

    it "records the current server time in last_processed_at when the run's threads are all processed" do
      allow(Time).to receive(:now).and_return(Time.at(1_700_000_500))
      described_class.new.perform

      expect(last_processed_at_store).to have_received(:store).with(user_id, "1700000500")
    end

    context "when more threads were found than have been processed" do
      let(:threads_processed_store) { instance_double(UserStore::CounterStore, increment: thread_ids.size) }
      let(:threads_found_store)     { instance_double(UserStore, fetch: (thread_ids.size * 10).to_s) }

      it "does not update last_processed_at while the run is still in progress" do
        allow(Time).to receive(:now).and_return(Time.at(1_700_000_500))
        described_class.new.perform

        expect(last_processed_at_store).not_to have_received(:store)
      end
    end

    context "when no threads were found for the run" do
      let(:threads_found_store) { instance_double(UserStore, fetch: "0") }

      it "does not update last_processed_at" do
        allow(Time).to receive(:now).and_return(Time.at(1_700_000_500))
        described_class.new.perform

        expect(last_processed_at_store).not_to have_received(:store)
      end
    end

    context "when last_processed_at is already at or after the current time" do
      let(:last_processed_at_store) { instance_double(UserStore, fetch: "9999999999", store: nil) }

      it "does not move last_processed_at backward" do
        allow(Time).to receive(:now).and_return(Time.at(1_700_000_500))
        described_class.new.perform

        expect(last_processed_at_store).not_to have_received(:store)
      end
    end

    context "when the stored max exceeds the new internal_date" do
      let(:threads_max_internal_date_store) { instance_double(UserStore, fetch: "9999999999999", store: nil) }

      it "does not update threads_max_internal_date" do
        described_class.new.perform

        expect(threads_max_internal_date_store).not_to have_received(:store)
      end

      it "still records last_processed_at" do
        allow(Time).to receive(:now).and_return(Time.at(1_700_000_500))
        described_class.new.perform

        expect(last_processed_at_store).to have_received(:store).with(user_id, "1700000500")
      end
    end

    it "increments portals_found by the number of unique portals sent to SQS" do
      described_class.new.perform

      expect(portals_found_store).to have_received(:increment).with(user_id, by: 1)
    end

    it "reschedules itself after processing" do
      described_class.new.perform

      expect(described_class).to have_received(:perform_in).with(Settings.thread_batch_worker_poll_interval)
    end

    context "when the same DamageReportRecord appears twice for the same user" do
      let(:fetcher) do
        instance_double(GmailThreadBatchFetcher).tap do |f|
          allow(f).to receive(:call).and_yield(gmail_message).and_yield(gmail_message)
        end
      end

      it "sends the portal only once" do
        described_class.new.perform

        expect(portal_sqs_client).to have_received(:send_messages)
          .with([portal.to_h],
                attributes: { UserStore::USER_ID_ATTR => user_id })
      end
    end

    context "when owned:false and owned:true have the same dedup key" do
      let(:portal_false) { DamageReportRecord.new(name: "ハチ公", latitude: "35.0", longitude: "139.0", owned: false, internal_date: 16999200) }
      let(:portal_true)  { DamageReportRecord.new(name: "ハチ公", latitude: "35.0", longitude: "139.0", owned: true,  internal_date: 16999200) }
      let(:decoder_false) { instance_double(EmailHtmlDecoder) }
      let(:decoder_true)  { instance_double(EmailHtmlDecoder) }
      let(:msg_false)     { instance_double(GmailMessage, html_decoder: decoder_false, internal_date:) }
      let(:msg_true)      { instance_double(GmailMessage, html_decoder: decoder_true,  internal_date:) }
      let(:fetcher) do
        instance_double(GmailThreadBatchFetcher).tap do |f|
          allow(f).to receive(:call).and_yield(msg_false).and_yield(msg_true)
        end
      end

      before do
        allow(decoder_false).to receive(:extract_portals).with(internal_date:).and_return([portal_false])
        allow(decoder_true).to  receive(:extract_portals).with(internal_date:).and_return([portal_true])
      end

      it "sends only the owned:true record" do
        described_class.new.perform

        expect(portal_sqs_client).to have_received(:send_messages)
          .with([portal_true.to_h],
                attributes: { UserStore::USER_ID_ATTR => user_id })
      end
    end

    context "when two messages have different user_ids with the same DamageReportRecord" do
      let(:other_user_id)      { "98765432109876543" }
      let(:other_access_token) { "ya29.other_token" }
      let(:other_token_store)  { instance_double(UserStore, fetch: other_access_token) }
      let(:other_message) do
        user_id_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: other_user_id)
        instance_double(
          Aws::SQS::Types::Message,
          body: JSON.generate(thread_ids),
          message_attributes: { UserStore::USER_ID_ATTR => user_id_attr },
          message_id: "msg-2",
          receipt_handle: "rh-2"
        )
      end

      before do
        allow(report_sqs_client).to receive(:receive_messages)
          .with(message_attribute_names: [UserStore::USER_ID_ATTR], max_messages: 1)
          .and_return([message], [other_message], [])
        allow(UserStore).to receive(:access_token).and_return(token_store, other_token_store)
        allow(GmailThreadBatchFetcher).to receive(:new).with(access_token: other_access_token).and_return(fetcher)
      end

      it "sends portals once per message with each user's user_id" do
        described_class.new.perform

        expect(portal_sqs_client).to have_received(:send_messages)
          .with([portal.to_h],
                attributes: { UserStore::USER_ID_ATTR => user_id })
        expect(portal_sqs_client).to have_received(:send_messages)
          .with([portal.to_h],
                attributes: { UserStore::USER_ID_ATTR => other_user_id })
      end

      it "deletes both messages" do
        described_class.new.perform

        expect(report_sqs_client).to have_received(:delete_messages).with("rh-1")
        expect(report_sqs_client).to have_received(:delete_messages).with("rh-2")
      end
    end

    context "when html_decoder returns nil" do
      let(:gmail_message) { instance_double(GmailMessage, html_decoder: nil, internal_date:) }

      it "does not call send_messages" do
        described_class.new.perform

        expect(portal_sqs_client).not_to have_received(:send_messages)
      end

      it "does not increment portals_found" do
        described_class.new.perform

        expect(portals_found_store).not_to have_received(:increment)
      end

      it "still deletes the message" do
        described_class.new.perform

        expect(report_sqs_client).to have_received(:delete_messages).with("rh-1")
      end
    end

    context "when an error occurs during processing" do
      before { allow(fetcher).to receive(:call).and_raise(RuntimeError) }

      it "still reschedules itself" do
        expect { described_class.new.perform }.to raise_error(RuntimeError)

        expect(described_class).to have_received(:perform_in).with(Settings.thread_batch_worker_poll_interval)
      end
    end

    context "when there are more messages than worker_max_messages_per_run" do
      before do
        allow(report_sqs_client).to receive(:receive_messages)
          .with(message_attribute_names: [UserStore::USER_ID_ATTR], max_messages: 1)
          .and_return(*Array.new(Settings.thread_batch_worker_max_messages_per_run + 1) { [message] })
      end

      it "stops after worker_max_messages_per_run messages" do
        described_class.new.perform

        expect(report_sqs_client).to have_received(:receive_messages)
          .exactly(Settings.thread_batch_worker_max_messages_per_run).times
      end
    end

    context "when the fetcher raises ApiError" do
      before { allow(fetcher).to receive(:call).and_raise(GmailClient::ApiError, "Gmail API error: 401") }

      it "re-raises" do
        expect { described_class.new.perform }.to raise_error(GmailClient::ApiError)
      end

      it "does not delete the message" do
        expect { described_class.new.perform }.to raise_error(GmailClient::ApiError)

        expect(report_sqs_client).not_to have_received(:delete_messages)
      end

      it "does not update threads_max_internal_date" do
        expect { described_class.new.perform }.to raise_error(GmailClient::ApiError)

        expect(threads_max_internal_date_store).not_to have_received(:store)
      end
    end

    context "when the lock is already held by another worker" do
      before do
        allow(REDIS).to receive(:set)
          .with(GmailThreadBatchWorker::LOCK_KEY, kind_of(String), nx: true, ex: Settings.thread_batch_worker_lock_ttl)
          .and_return(nil)
      end

      it "skips processing" do
        described_class.new.perform
        expect(report_sqs_client).not_to have_received(:receive_messages)
      end

      it "reschedules itself after worker_poll_interval" do
        described_class.new.perform
        expect(described_class).to have_received(:perform_in).with(Settings.thread_batch_worker_poll_interval)
      end
    end

    context "when the lock is acquired" do
      it "releases the lock in ensure" do
        described_class.new.perform
        expect(REDIS).to have_received(:eval)
          .with(PollingWorker::RELEASE_LOCK_SCRIPT, keys: [GmailThreadBatchWorker::LOCK_KEY], argv: [kind_of(String)])
      end

      it "releases the lock even when processing raises" do
        allow(fetcher).to receive(:call).and_raise(RuntimeError)
        expect { described_class.new.perform }.to raise_error(RuntimeError)
        expect(REDIS).to have_received(:eval)
          .with(PollingWorker::RELEASE_LOCK_SCRIPT, keys: [GmailThreadBatchWorker::LOCK_KEY], argv: [kind_of(String)])
      end
    end
  end

  describe "Sidekiq options" do
    it "does not retry" do
      expect(described_class.sidekiq_options["retry"]).to eq(0)
    end
  end
end
