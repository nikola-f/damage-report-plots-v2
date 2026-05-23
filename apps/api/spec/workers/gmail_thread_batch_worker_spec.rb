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
  let(:fetcher)       { instance_double(GmailThreadBatchFetcher, call: [gmail_message]) }

  let(:message) do
    user_id_attr = instance_double(Aws::SQS::Types::MessageAttributeValue, string_value: user_id)
    instance_double(
      Aws::SQS::Types::Message,
      body: JSON.generate(thread_ids),
      message_attributes: { UserStore::USER_ID_ATTR => user_id_attr }
    )
  end

  before do
    allow(REDIS).to receive(:set)
      .with(GmailThreadBatchWorker::LOCK_KEY, "1", nx: true, ex: GmailThreadBatchWorker::LOCK_TTL)
      .and_return("OK")
    allow(REDIS).to receive(:del).with(GmailThreadBatchWorker::LOCK_KEY)
    allow(SqsClient).to receive(:new).with(Settings.sqs_reports_queue_url).and_return(portal_sqs_client)
    allow(SqsClient).to receive(:new).with(Settings.sqs_thread_ids_queue_url).and_return(report_sqs_client)
    allow(report_sqs_client).to receive(:poll).and_yield(message)
    allow(UserStore).to receive(:access_token).and_return(token_store)
    allow(GmailThreadBatchFetcher).to receive(:new).and_return(fetcher)
    allow(decoder).to receive(:extract_portals).with(internal_date:).and_return([portal])
    allow(described_class).to receive(:perform_in)
  end

  describe "#perform" do
    it "polls the report queue with user_id attribute" do
      described_class.new.perform

      expect(report_sqs_client).to have_received(:poll).with(message_attribute_names: [UserStore::USER_ID_ATTR])
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
        .with([portal.to_h], attributes: { UserStore::USER_ID_ATTR => user_id })
    end

    it "reschedules itself after polling" do
      described_class.new.perform

      expect(described_class).to have_received(:perform_in).with(GmailThreadBatchWorker::POLL_INTERVAL)
    end

    context "when the same DamageReportRecord appears twice for the same user" do
      let(:fetcher) { instance_double(GmailThreadBatchFetcher, call: [gmail_message, gmail_message]) }

      it "sends the portal only once" do
        described_class.new.perform

        expect(portal_sqs_client).to have_received(:send_messages)
          .with([portal.to_h], attributes: { UserStore::USER_ID_ATTR => user_id })
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
          message_attributes: { UserStore::USER_ID_ATTR => user_id_attr }
        )
      end

      before do
        allow(report_sqs_client).to receive(:poll).and_yield(message).and_yield(other_message)
        allow(UserStore).to receive(:access_token).and_return(token_store, other_token_store)
        allow(GmailThreadBatchFetcher).to receive(:new).with(access_token: other_access_token).and_return(fetcher)
      end

      it "sends portals once per user with each user's user_id" do
        described_class.new.perform

        expect(portal_sqs_client).to have_received(:send_messages)
          .with([portal.to_h], attributes: { UserStore::USER_ID_ATTR => user_id })
        expect(portal_sqs_client).to have_received(:send_messages)
          .with([portal.to_h], attributes: { UserStore::USER_ID_ATTR => other_user_id })
      end
    end

    context "when html_decoder returns nil" do
      let(:gmail_message) { instance_double(GmailMessage, html_decoder: nil) }

      it "does not call send_messages" do
        described_class.new.perform

        expect(portal_sqs_client).not_to have_received(:send_messages)
      end
    end

    context "when an error occurs during processing" do
      before { allow(report_sqs_client).to receive(:poll).and_raise(RuntimeError) }

      it "still reschedules itself" do
        expect { described_class.new.perform }.to raise_error(RuntimeError)

        expect(described_class).to have_received(:perform_in).with(GmailThreadBatchWorker::POLL_INTERVAL)
      end
    end

    context "when the fetcher raises ApiError" do
      before { allow(fetcher).to receive(:call).and_raise(GmailClient::ApiError, "Gmail API error: 401") }

      it "re-raises" do
        expect { described_class.new.perform }.to raise_error(GmailClient::ApiError)
      end
    end

    context "when the lock is already held by another worker" do
      before do
        allow(REDIS).to receive(:set)
          .with(GmailThreadBatchWorker::LOCK_KEY, "1", nx: true, ex: GmailThreadBatchWorker::LOCK_TTL)
          .and_return(nil)
      end

      it "skips processing" do
        described_class.new.perform
        expect(report_sqs_client).not_to have_received(:poll)
      end

      it "does not reschedule itself" do
        described_class.new.perform
        expect(described_class).not_to have_received(:perform_in)
      end
    end

    context "when the lock is acquired" do
      it "releases the lock in ensure" do
        described_class.new.perform
        expect(REDIS).to have_received(:del).with(GmailThreadBatchWorker::LOCK_KEY)
      end

      it "releases the lock even when processing raises" do
        allow(report_sqs_client).to receive(:poll).and_raise(RuntimeError)
        expect { described_class.new.perform }.to raise_error(RuntimeError)
        expect(REDIS).to have_received(:del).with(GmailThreadBatchWorker::LOCK_KEY)
      end
    end
  end

  describe "Sidekiq options" do
    it "does not retry" do
      expect(described_class.sidekiq_options["retry"]).to eq(0)
    end
  end
end
