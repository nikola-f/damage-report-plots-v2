# frozen_string_literal: true

class SpreadsheetSyncWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  POLL_INTERVAL = 30  # seconds
  SHEET_NAME    = "reports"
  LOCK_KEY      = "spreadsheet_sync_worker:lock"
  LOCK_TTL      = 300 # seconds

  def perform
    acquired = REDIS.set(LOCK_KEY, "1", nx: true, ex: LOCK_TTL)

    unless acquired
      logger.debug "another SpreadsheetSyncWorker is running, skipping"
      self.class.perform_in(POLL_INTERVAL)
      return
    end

    begin
      sqs = SqsClient.new(Settings.sqs_reports_queue_url)

      loop do
        messages = sqs.receive_messages(
          message_attribute_names: [UserStore::USER_ID_ATTR],
          max_messages: 10
        )
        break if messages.empty?

        batch = Hash.new { |h, k| h[k] = { records: [], handles: [] } }
        messages.each do |message|
          user_id = message.message_attributes[UserStore::USER_ID_ATTR].string_value
          records = JSON.parse(message.body).map { |h| DamageReportRecord.new(**h.transform_keys(&:to_sym)) }
          batch[user_id][:records].concat(records)
          batch[user_id][:handles] << message.receipt_handle
        end

        batch.each do |user_id, data|
          logger.debug "received #{data[:records].size} records for user #{user_id}"
          process(user_id:, records: data[:records])
          sqs.delete_messages(data[:handles])
          logger.debug "deleted #{data[:handles].size} messages for user #{user_id}"
        end
      end
    ensure
      REDIS.del(LOCK_KEY)
      self.class.perform_in(POLL_INTERVAL)
    end
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
