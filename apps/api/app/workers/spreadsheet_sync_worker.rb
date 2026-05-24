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
      return
    end

    begin
      sqs = SqsClient.new(Settings.sqs_reports_queue_url)

      loop do
        messages = sqs.receive_messages(
          message_attribute_names: [UserStore::USER_ID_ATTR],
          max_messages: 1
        )
        break if messages.empty?

        message = messages.first
        user_id = message.message_attributes[UserStore::USER_ID_ATTR].string_value
        records = JSON.parse(message.body).map { |h| DamageReportRecord.new(**h.transform_keys(&:to_sym)) }
        logger.debug "received #{records.size} records for user #{user_id}"

        process(user_id:, records:)

        sqs.delete_messages(message.receipt_handle)
        logger.debug "deleted records message for user #{user_id}"
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
      record.latitude,
      record.longitude,
      record.owned ? 1 : 0,
      "#{record.internal_date},#{record.name}",
      Time.now.strftime("%y%m%d%H%M%S").to_i
    ]
  end

end
