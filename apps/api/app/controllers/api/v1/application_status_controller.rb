# frozen_string_literal: true

module Api
  module V1
    class ApplicationStatusController < ApplicationController
      include Authenticatable

      def show
        render json: {
          gmail_quota: gmail_quota_status,
          sqs_queues:  sqs_queue_status
        }, status: :ok
      end

      private

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
        {
          thread_ids: SqsClient.new(Settings.sqs_report_queue_url).queue_depth,
          reports:    SqsClient.new(Settings.sqs_portal_queue_url).queue_depth
        }
      end
    end
  end
end
