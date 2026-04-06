# frozen_string_literal: true

class GmailThreadBatchWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds

  def perform
    sqs = SqsClient.new(Settings.sqs_portal_queue_url)

    SqsPoller.new(
      queue_url: Settings.sqs_report_queue_url,
      message_attribute_names: ["token_key"]
    ).poll do |message|
      token_key    = message.message_attributes["token_key"].string_value
      thread_ids   = JSON.parse(message.body)
      access_token = AccessTokenStore.new.fetch(token_key)

      GmailThreadBatchFetcher.new(access_token:).call(thread_ids).each do |gmail_message|
        gmail_message.html_decoder&.extract_portals&.each do |portal|
          sqs.send_message(portal)
        end
      end
    end
  ensure
    self.class.perform_in(POLL_INTERVAL)
  end
end
