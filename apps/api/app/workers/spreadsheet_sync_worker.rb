# frozen_string_literal: true

class SpreadsheetSyncWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds
  SHEET_NAME    = "Attacks"

  def perform
    SqsClient.new(Settings.sqs_portal_queue_url).poll(message_attribute_names: [AccessTokenStore::TOKEN_KEY_ATTR]) do |message|
      token_key = message.message_attributes[AccessTokenStore::TOKEN_KEY_ATTR].string_value
      records   = JSON.parse(message.body).map { |h| DamageReportRecord.new(**h.transform_keys(&:to_sym)) }

      process(token_key:, records:)
    end
  ensure
    self.class.perform_in(POLL_INTERVAL)
  end

  private

  def process(token_key:, records:)
    access_token   = AccessTokenStore.new.fetch(token_key)
    spreadsheet_id = SpreadsheetIdStore.new.fetch(token_key)
    rows           = records.map { |r| to_row(r) }

    SpreadsheetsClient.new(access_token).append_rows(
      spreadsheet_id: spreadsheet_id,
      sheet_name:     SHEET_NAME,
      rows:           rows
    )
  end

  def to_row(_record)
    raise NotImplementedError, "to_row is not yet implemented"
  end
end
