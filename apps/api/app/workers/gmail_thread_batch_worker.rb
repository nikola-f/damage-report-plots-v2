# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL        = 30  # seconds
  LOCK_KEY             = "gmail_thread_batch_worker:lock"
  LOCK_TTL             = 900 # seconds; covers actual processing time (~530s observed)
  PORTALS_CHUNK_SIZE   = 10 * 1024 # bytes; keeps send_message_batch well under SQS 1MB batch limit
  MAX_MESSAGES_PER_RUN = 5

  def perform
    acquired = REDIS.set(LOCK_KEY, "1", nx: true, ex: LOCK_TTL)

    unless acquired
      logger.debug "another GmailThreadBatchWorker is running, skipping"
      self.class.perform_in(POLL_INTERVAL)
      return
    end

    begin
      portal_sqs = SqsClient.new(Settings.sqs_reports_queue_url)
      thread_sqs = SqsClient.new(Settings.sqs_thread_ids_queue_url)

      processed = 0
      loop do
        break if processed >= MAX_MESSAGES_PER_RUN

        messages = thread_sqs.receive_messages(
          message_attribute_names: [UserStore::USER_ID_ATTR],
          max_messages: 1
        )
        break if messages.empty?

        message    = messages.first
        user_id    = message.message_attributes[UserStore::USER_ID_ATTR].string_value
        thread_ids = JSON.parse(message.body)
        logger.debug "received #{thread_ids.size} thread_ids for user #{user_id}"

        access_token   = UserStore.access_token.fetch(user_id)
        gmail_messages = GmailThreadBatchFetcher.new(access_token:).call(thread_ids)
        logger.debug "fetched #{gmail_messages.size} gmail messages"

        portals = []
        gmail_messages.each do |gmail_message|
          gmail_message.html_decoder&.extract_portals(internal_date: gmail_message.internal_date)&.each do |portal|
            portals << portal
          end
        end

        unique_portals = DamageReportRecord.deduplicate(portals)
        if unique_portals.any?
          portal_sqs.send_messages(unique_portals.map(&:to_h),
                                   attributes: { UserStore::USER_ID_ATTR => user_id },
                                   max_message_size: PORTALS_CHUNK_SIZE)
          logger.debug "sent #{unique_portals.size} portals to SQS for user #{user_id}"
        end

        thread_sqs.delete_messages(message.receipt_handle)
        logger.debug "deleted thread_ids message for user #{user_id}"
        processed += 1
      end
    ensure
      REDIS.del(LOCK_KEY)
      self.class.perform_in(POLL_INTERVAL)
    end
  end
end
