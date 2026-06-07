# frozen_string_literal: true

class SpreadsheetSyncWorker
  include Sidekiq::Worker
  include PollingWorker

  sidekiq_options retry: 0

  SHEET_NAME = "reports"
  LOCK_KEY   = "spreadsheet_sync_worker:lock"

  def perform
    with_lock(key: LOCK_KEY, ttl: Settings.spreadsheet_sync_worker_lock_ttl, interval: Settings.spreadsheet_sync_worker_poll_interval) do
      sqs       = SqsClient.new(Settings.sqs_reports_queue_url)
      limit     = Settings.spreadsheet_sync_worker_max_messages_per_run
      processed = 0

      loop do
        remaining = limit - processed
        break if remaining <= 0

        messages = sqs.receive_messages(
          message_attribute_names: [UserStore::USER_ID_ATTR],
          max_messages: [remaining, 10].min
        )
        break if messages.empty?

        build_batch(messages).each do |user_id, data|
          logger.debug "received #{data[:records].size} records for user #{user_id}"
          process(user_id:, records: data[:records])
          sqs.delete_messages(data[:handles])
          logger.debug "deleted #{data[:handles].size} messages for user #{user_id}"
        end
        processed += messages.size
      end
    end
  end

  private

  def build_batch(messages)
    Hash.new { |h, k| h[k] = { records: [], handles: [] } }.tap do |batch|
      messages.each do |message|
        user_id = message.message_attributes[UserStore::USER_ID_ATTR].string_value
        records = JSON.parse(message.body).map { |h| DamageReportRecord.from_h(h) }
        batch[user_id][:records].concat(records)
        batch[user_id][:handles] << message.receipt_handle
      end
    end
  end

  def process(user_id:, records:)
    access_token   = UserStore.access_token.fetch(user_id)
    spreadsheet_id = UserStore.spreadsheet_id.fetch(user_id)
    rows           = records.map { |r| to_row(r) }

    SpreadsheetsClient.new(access_token).append_rows(
      spreadsheet_id: spreadsheet_id,
      sheet_name:     SHEET_NAME,
      rows:           rows
    )
    UserStore.portals_appended.increment(user_id, by: rows.size)
    logger.debug "appended #{rows.size} rows for user #{user_id}"
  end

  def to_row(record)
    [
      record.portal_id,
      record.latitude.to_f,
      record.longitude.to_f,
      record.owned ? 1 : 0,
      "#{record.internal_date},#{record.name}",
      Time.now.strftime("%y%m%d%H%M%S").to_i
    ]
  end
end
