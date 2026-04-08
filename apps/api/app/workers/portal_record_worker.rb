# frozen_string_literal: true

class PortalRecordWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds

  def perform
    SqsClient.new(Settings.sqs_portal_queue_url).poll(message_attribute_names: [AccessTokenStore::TOKEN_KEY_ATTR]) do |message|
      token_key = message.message_attributes[AccessTokenStore::TOKEN_KEY_ATTR].string_value
      portals   = JSON.parse(message.body).map { |h| PortalRecord.new(**h.transform_keys(&:to_sym)) }

      process(token_key:, portals:)
    end
  ensure
    self.class.perform_in(POLL_INTERVAL)
  end

  private

  def process(token_key:, portals:)
    # TODO: implement
  end
end
