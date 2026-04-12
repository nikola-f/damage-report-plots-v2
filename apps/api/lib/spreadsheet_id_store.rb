# frozen_string_literal: true

# Stores Google Spreadsheet IDs. No TTL — persists as long as Redis data survives.
class SpreadsheetIdStore < UserStore
  KEY_PREFIX = "spreadsheet_id"
  TTL        = nil
end
