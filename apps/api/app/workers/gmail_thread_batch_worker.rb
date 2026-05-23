# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30  # seconds
  LOCK_KEY      = "gmail_thread_batch_worker:lock"
  LOCK_TTL      = 300 # seconds; covers worst-case 6 retries × 32s max backoff

  def perform
    acquired = REDIS.set(LOCK_KEY, "1", nx: true, ex: LOCK_TTL)

    unless acquired
      logger.debug "another GmailThreadBatchWorker is running, skipping"
      return
    end

    begin
      sqs             = SqsClient.new(Settings.sqs_reports_queue_url)
      portals_by_user = Hash.new { |h, k| h[k] = [] }

      SqsClient.new(Settings.sqs_thread_ids_queue_url).poll(message_attribute_names: [UserStore::USER_ID_ATTR]) do |message|
        user_id      = message.message_attributes[UserStore::USER_ID_ATTR].string_value
        thread_ids   = JSON.parse(message.body)
        logger.debug "received #{thread_ids.size} thread_ids for user #{user_id}"

        access_token   = UserStore.access_token.fetch(user_id)
        gmail_messages = GmailThreadBatchFetcher.new(access_token:).call(thread_ids)
        logger.debug "fetched #{gmail_messages.size} gmail messages"

        gmail_messages.each do |gmail_message|
          gmail_message.html_decoder&.extract_portals(internal_date: gmail_message.internal_date)&.each do |portal|
            portals_by_user[user_id] << portal
          end
        end
      end

      if portals_by_user.empty?
        logger.debug "no portals to send"
      else
        portals_by_user.each do |user_id, portals|
          unique_portals = portals.uniq
          sqs.send_messages(unique_portals.map(&:to_h), attributes: { UserStore::USER_ID_ATTR => user_id })
          logger.debug "sent #{unique_portals.size} portals to SQS for user #{user_id}"
        end
      end
    ensure
      REDIS.del(LOCK_KEY)
      self.class.perform_in(POLL_INTERVAL)
    end
  end
end
