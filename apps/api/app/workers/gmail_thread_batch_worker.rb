# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds

  def perform
    sqs              = SqsClient.new(Settings.sqs_portal_queue_url)
    portals_by_token = Hash.new { |h, k| h[k] = [] }

    SqsClient.new(Settings.sqs_report_queue_url).poll(message_attribute_names: ["token_key"]) do |message|
      token_key    = message.message_attributes["token_key"].string_value
      thread_ids   = JSON.parse(message.body)
      access_token = AccessTokenStore.new.fetch(token_key)

      GmailThreadBatchFetcher.new(access_token:).call(thread_ids).each do |gmail_message|
        gmail_message.html_decoder&.extract_portals(internal_date: gmail_message.internal_date)&.each do |portal|
          portals_by_token[token_key] << portal
        end
      end
    end

    portals_by_token.each do |token_key, portals|
      sqs.send_messages(portals.uniq.map(&:to_h), attributes: { "token_key" => token_key })
    end
  ensure
    self.class.perform_in(POLL_INTERVAL)
  end
end
