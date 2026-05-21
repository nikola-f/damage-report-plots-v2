# frozen_string_literal: true

Sidekiq.configure_client do |config|
  config.redis = { url: Settings.redis_url }
end

Sidekiq.configure_server do |config|
  config.redis = { url: Settings.redis_url }
  config.logger.level = Logger.const_get(ENV.fetch("RAILS_LOG_LEVEL", "info").upcase)

  config.on(:startup) do
    GmailThreadBatchWorker.perform_async
    SpreadsheetSyncWorker.perform_async
  end
end
