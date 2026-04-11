# frozen_string_literal: true

class SpreadsheetSyncWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds
  SHEET_NAME    = "Attacks"

  # Printable ASCII excluding " (breaks CSV) and ' (Sheets text prefix).
  # Larger alphabet → shorter Sqids IDs.
  SQIDS_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-./:;<=>?@[\\]^_`{|}~"

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

  def to_row(record)
    [
      portal_id(record),
      record.latitude,
      record.longitude,
      record.owned ? 1 : 0,
      "#{record.internal_date},#{record.name}",
      Time.now.strftime("%y%m%d%H%M%S").to_i
    ]
  end

  def portal_id(record)
    lat_int = ((record.latitude.to_f + 90) * 1_000_000).round
    lng_int = ((record.longitude.to_f + 180) * 1_000_000).round
    Sqids.new(alphabet: SQIDS_ALPHABET).encode([lat_int, lng_int])
  end
end
