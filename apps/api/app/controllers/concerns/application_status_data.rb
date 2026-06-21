# frozen_string_literal: true

module ApplicationStatusData
  private

  def application_status
    {
      sqs_queues: sqs_queue_status
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
