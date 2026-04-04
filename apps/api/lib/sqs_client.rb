# frozen_string_literal: true

require "aws-sdk-sqs"
require "digest"
require "json"

class SqsClient
  MAX_RECEIVE_MESSAGES = 1_000

  # @param queue_url [String] SQS FIFO queue URL (must end with .fifo)
  # @param message_group_id [String] FIFO message group ID for ordering
  # @param wait_time_seconds [Integer] long polling wait time in seconds (0-20, 0 = short polling)
  # @param client [Aws::SQS::Client, nil] injectable for testing
  def initialize(queue_url, message_group_id: "default", wait_time_seconds: 20, client: nil)
    @queue_url         = queue_url
    @message_group_id  = message_group_id
    @wait_time_seconds = wait_time_seconds
    @client            = client || Aws::SQS::Client.new
  end

  # Sends a single message to SQS FIFO queue.
  #
  # @param message [#to_h] Value object with a #to_h method (e.g. ReportTask)
  # @param attributes [Hash] optional metadata ({ "key" => value, ... })
  #   Values are typed automatically: Numeric => Number, others => String
  # @return [Aws::SQS::Types::SendMessageResult]
  def send_message(message, attributes: {})
    body = JSON.generate(message.to_h)

    @client.send_message(
      queue_url:                @queue_url,
      message_body:             body,
      message_group_id:         @message_group_id,
      message_deduplication_id: deduplication_id(body),
      message_attributes:       build_message_attributes(attributes)
    )
  end

  # Sends multiple messages to SQS FIFO queue, batching automatically in groups of 10.
  #
  # @param messages [Array<#to_h>] Array of value objects
  # @param attributes [Hash] optional metadata applied to every message ({ "key" => value, ... })
  #   Values are typed automatically: Numeric => Number, others => String
  # @return [Array<Aws::SQS::Types::SendMessageBatchResult>]
  def send_messages(messages, attributes: {})
    sqs_attributes = build_message_attributes(attributes)

    messages.each_slice(10).map do |batch|
      entries = batch.each_with_index.map do |message, index|
        body = message
        {
          id:                       index.to_s,
          message_body:             body,
          message_group_id:         @message_group_id,
          message_deduplication_id: deduplication_id(body),
          message_attributes:       sqs_attributes
        }
      end

      @client.send_message_batch(
        queue_url: @queue_url,
        entries:   entries
      )
    end
  end

  # Receives up to MAX_RECEIVE_MESSAGES messages from SQS, fetching in batches of 10.
  # Uses long polling by default (wait_time_seconds: 20).
  #
  # Received messages are invisible to other consumers until the visibility
  # timeout expires. Call #delete_messages after successful processing.
  #
  # Note: SQS may return fewer messages than requested even when more exist.
  # This method stops early if an empty response is returned.
  #
  # @return [Array<Aws::SQS::Types::Message>] each element has .body, .receipt_handle, and .message_attributes
  def receive_messages
    remaining = MAX_RECEIVE_MESSAGES
    messages  = []

    while remaining > 0
      batch_size = [remaining, 10].min
      response   = @client.receive_message(
        queue_url:              @queue_url,
        max_number_of_messages: batch_size,
        wait_time_seconds:      @wait_time_seconds
      )
      break if response.messages.empty?

      messages  += response.messages
      remaining -= response.messages.size
    end

    messages
  end

  # Deletes one or more messages from SQS after successful processing.
  # Batches automatically in groups of 10.
  #
  # @param receipt_handles [String, Array<String>] receipt handle(s) from received messages
  # @return [Array<Aws::SQS::Types::DeleteMessageBatchResult>]
  def delete_messages(*receipt_handles)
    receipt_handles.flatten.each_slice(10).map do |batch|
      entries = batch.each_with_index.map do |handle, index|
        { id: index.to_s, receipt_handle: handle }
      end

      @client.delete_message_batch(
        queue_url: @queue_url,
        entries:   entries
      )
    end
  end

  class SendError < StandardError; end

  private

  def deduplication_id(body)
    Digest::SHA256.hexdigest(body)
  end

  # Converts a plain Ruby hash to SQS message attribute format.
  # Numeric values are typed as "Number", all others as "String".
  #
  # @param attributes [Hash] e.g. { "source" => "gmail", "retry_count" => 0 }
  # @return [Hash] SQS message attribute hash
  def build_message_attributes(attributes)
    attributes.transform_values do |value|
      if value.is_a?(Numeric)
        { data_type: "Number", string_value: value.to_s }
      else
        { data_type: "String", string_value: value.to_s }
      end
    end
  end
end
