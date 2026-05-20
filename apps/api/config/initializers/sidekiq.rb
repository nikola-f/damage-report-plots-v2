# frozen_string_literal: true

Sidekiq.configure_client do |config|
  config.redis = { url: Settings.redis_url }
end

Sidekiq.configure_server do |config|
  config.redis = { url: Settings.redis_url }

  config.on(:startup) do
    GmailThreadBatchWorker.perform_async
    SpreadsheetSyncWorker.perform_async
  end
end
