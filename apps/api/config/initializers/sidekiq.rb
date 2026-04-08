# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.on(:startup) do
    GmailThreadBatchWorker.perform_async
    DamageReportSheetWorker.perform_async
  end
end
