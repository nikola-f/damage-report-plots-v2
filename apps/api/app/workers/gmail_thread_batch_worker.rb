# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds
  MAX_BACKOFF   = 32 # seconds; exponential backoff cap for Gmail 429 / quota errors

  def perform
    sqs             = SqsClient.new(Settings.sqs_reports_queue_url)
    portals_by_user = Hash.new { |h, k| h[k] = [] }

    SqsClient.new(Settings.sqs_thread_ids_queue_url).poll(message_attribute_names: [UserStore::USER_ID_ATTR]) do |message|
      user_id      = message.message_attributes[UserStore::USER_ID_ATTR].string_value
      thread_ids   = JSON.parse(message.body)
      access_token = UserStore.access_token.fetch(user_id)

      with_backoff { GmailThreadBatchFetcher.new(access_token:).call(thread_ids) }.each do |gmail_message|
        gmail_message.html_decoder&.extract_portals(internal_date: gmail_message.internal_date)&.each do |portal|
          portals_by_user[user_id] << portal
        end
      end
    end

    portals_by_user.each do |user_id, portals|
      sqs.send_messages(portals.uniq.map(&:to_h), attributes: { UserStore::USER_ID_ATTR => user_id })
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
      sleep [2**attempt, MAX_BACKOFF].min
      attempt += 1
      retry
    rescue GmailClient::QuotaExceededError
      sleep [2**attempt, MAX_BACKOFF].min
      attempt += 1
      retry
    end
  end
end
