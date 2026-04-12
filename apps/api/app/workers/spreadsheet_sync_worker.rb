# frozen_string_literal: true

require "digest"

class SpreadsheetSyncWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30 # seconds
  SHEET_NAME    = JSON.load_file(SpreadsheetsClient::DEFINITION_PATH)
                    .dig("sheets", 0, "properties", "title")

  # Printable ASCII excluding " (breaks CSV) and ' (Sheets text prefix).
  # Larger alphabet → shorter Sqids IDs.
  SQIDS_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-./:;<=>?@[]^_`{|}~"
  SQIDS          = Sqids.new(alphabet: SQIDS_ALPHABET)

  def perform
    SqsClient.new(Settings.sqs_portal_queue_url).poll(
      message_attribute_names: [UserStore::USER_ID_ATTR]
    ) do |message|
      user_id = message.message_attributes[UserStore::USER_ID_ATTR].string_value
      records = JSON.parse(message.body).map { |h| DamageReportRecord.new(**h.transform_keys(&:to_sym)) }

      process(user_id:, records:)
    end
  ensure
    self.class.perform_in(POLL_INTERVAL)
  end

  private

  def process(user_id:, records:)
    access_token   = UserStore.access_token.fetch(user_id)
    spreadsheet_id = UserStore.spreadsheet_id.fetch(user_id)
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
    hash   = Digest::SHA256.digest("#{record.latitude},#{record.longitude}")
    number = hash.unpack1("Q>") & ((1 << 62) - 1) # Sqids max: 2^62 - 1
    SQIDS.encode([number])
  end
end
