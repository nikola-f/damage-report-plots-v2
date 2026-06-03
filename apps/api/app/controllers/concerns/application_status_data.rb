# frozen_string_literal: true

module ApplicationStatusData
  private

  def application_status
    {
      gmail_quota: gmail_quota_status,
      sqs_queues:  sqs_queue_status
    }
  end

  def gmail_quota_status
    used      = REDIS.get("gmail_quota:project").to_i
    ttl       = REDIS.ttl("gmail_quota:project")
    resets_in = ttl.positive? ? ttl : 0
    {
      used:              used,
      limit:             GmailClient::PER_PROJECT_LIMIT,
      remaining:         GmailClient::PER_PROJECT_LIMIT - used,
      window_seconds:    GmailClient::QUOTA_WINDOW,
      resets_in_seconds: resets_in
    }
  end

  def sqs_queue_status
    thread_ids = SqsClient.new(Settings.sqs_thread_ids_queue_url).queue_depth
    reports    = SqsClient.new(Settings.sqs_reports_queue_url).queue_depth
    {
      thread_ids: thread_ids[:available] + thread_ids[:in_flight],
      reports:    reports[:available]    + reports[:in_flight]
    }
  end
end
