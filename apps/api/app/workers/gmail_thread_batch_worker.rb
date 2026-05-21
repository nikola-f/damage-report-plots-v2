# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds
  MAX_BACKOFF   = 32 # seconds; exponential backoff cap for Gmail 429 / quota errors
  MAX_RETRIES   = 6  # 1+2+4+8+16+32 = 63s total wait, covering one quota window

  def perform
    sqs             = SqsClient.new(Settings.sqs_reports_queue_url)
    portals_by_user = Hash.new { |h, k| h[k] = [] }

    SqsClient.new(Settings.sqs_thread_ids_queue_url).poll(message_attribute_names: [UserStore::USER_ID_ATTR]) do |message|
      user_id      = message.message_attributes[UserStore::USER_ID_ATTR].string_value
      thread_ids   = JSON.parse(message.body)
      logger.debug "received #{thread_ids.size} thread_ids for user #{user_id}"

      access_token   = UserStore.access_token.fetch(user_id)
      gmail_messages = with_backoff { GmailThreadBatchFetcher.new(access_token:).call(thread_ids) }
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
    self.class.perform_in(POLL_INTERVAL)
  end

  private

  def with_backoff
    attempt = 0
    begin
      yield
    rescue GmailClient::ApiError => e
      raise unless e.message.include?("429")
      raise if attempt >= MAX_RETRIES
      sleep [2**attempt, MAX_BACKOFF].min
      attempt += 1
      retry
    rescue GmailClient::QuotaExceededError
      raise if attempt >= MAX_RETRIES
      sleep [2**attempt, MAX_BACKOFF].min
      attempt += 1
      retry
    end
  end
end
