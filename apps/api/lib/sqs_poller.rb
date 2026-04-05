# frozen_string_literal: true

# Generic SQS polling utility.
# Receives messages from a queue, yields each to the caller, then deletes them.
#
# @example
#   SqsPoller.new(queue_url: Settings.sqs_report_queue_url,
#                 message_attribute_names: ["token_key"]).poll do |message|
#     token_key  = message.message_attributes["token_key"].string_value
#     thread_ids = JSON.parse(message.body)
#     MyWorker.perform_async(token_key, thread_ids)
#   end
class SqsPoller
  # @param queue_url [String]
  # @param message_attribute_names [Array<String>] SQS attribute names to retrieve with each message
  def initialize(queue_url:, message_attribute_names: [])
    @sqs                     = SqsClient.new(queue_url)
    @message_attribute_names = message_attribute_names
  end

  # Receives messages, yields each, then deletes all.
  # No messages are deleted if none are received.
  #
  # @yield [Aws::SQS::Types::Message]
  def poll
    messages = @sqs.receive_messages(message_attribute_names: @message_attribute_names)
    messages.each { |msg| yield msg }
    @sqs.delete_messages(messages.map(&:receipt_handle)) if messages.any?
  end
end
