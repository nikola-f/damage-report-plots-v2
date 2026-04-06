# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds

  def perform
    sqs              = SqsClient.new(Settings.sqs_portal_queue_url)
    portals_by_token = Hash.new { |h, k| h[k] = [] }

    SqsPoller.new(
      queue_url: Settings.sqs_report_queue_url,
      message_attribute_names: ["token_key"]
    ).poll do |message|
      token_key    = message.message_attributes["token_key"].string_value
      thread_ids   = JSON.parse(message.body)
      access_token = AccessTokenStore.new.fetch(token_key)

      GmailThreadBatchFetcher.new(access_token:).call(thread_ids).each do |gmail_message|
        gmail_message.html_decoder&.extract_portals(internal_date: gmail_message.internal_date)&.each do |portal|
          portals_by_token[token_key] << portal
        end
      end
    end

    portals_by_token.each_value do |portals|
      portals.uniq.each { |portal| sqs.send_message(portal) }
    end
  ensure
    self.class.perform_in(POLL_INTERVAL)
  end
end
