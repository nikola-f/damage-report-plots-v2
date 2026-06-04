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

  # Sends multiple items to SQS FIFO queue as a single JSON array message.
  #
  # @param items [Array] JSON-serializable items to enqueue (e.g. Array<String>, Array<Hash>)
  # @param attributes [Hash] optional metadata applied to the message ({ "key" => value, ... })
  #   Values are typed automatically: Numeric => Number, others => String
  # @return [Aws::SQS::Types::SendMessageResult]
  def send_messages(items, attributes: {})
    body = JSON.generate(items)
    @client.send_message(
      queue_url: @queue_url,
      message_body: body,
      message_group_id: @message_group_id,
      message_deduplication_id: deduplication_id(body),
      message_attributes: build_message_attributes(attributes)
    )
  end

  # Receives messages, yields each to the block, then deletes them all.
  #
  # @param message_attribute_names [Array<String>] SQS message attribute names to retrieve
  # @yieldparam message [Aws::SQS::Types::Message]
  def poll(message_attribute_names: [], max_messages: MAX_RECEIVE_MESSAGES, &block)
    messages = receive_messages(message_attribute_names:, max_messages:)
    messages.each { |msg| block.call(msg) }
    delete_messages(messages.map(&:receipt_handle)) if messages.any?
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
  # @param message_attribute_names [Array<String>] SQS message attribute names to retrieve (e.g. ["token_key"])
  # @param max_messages [Integer] maximum number of messages to receive (default: MAX_RECEIVE_MESSAGES)
  # @return [Array<Aws::SQS::Types::Message>] each element has .body, .receipt_handle, and .message_attributes
  def receive_messages(message_attribute_names: [], max_messages: MAX_RECEIVE_MESSAGES)
    remaining = max_messages
    messages  = []

    while remaining.positive?
      batch_size = [remaining, 10].min
      params = {
        queue_url: @queue_url,
        max_number_of_messages: batch_size,
        wait_time_seconds: @wait_time_seconds
      }
      params[:message_attribute_names] = message_attribute_names if message_attribute_names.any?

      response = @client.receive_message(**params)
      break if response.messages.empty?

      messages  += response.messages
      remaining -= response.messages.size
    end

    messages
  end

  # Returns the approximate number of messages in the queue.
  #
  # @return [Hash] { available: Integer, in_flight: Integer }
  #   available  - messages visible to consumers
  #   in_flight  - messages currently being processed (invisible)
  def queue_depth
    response = @client.get_queue_attributes(
      queue_url:       @queue_url,
      attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
    )
    {
      available: response.attributes["ApproximateNumberOfMessages"].to_i,
      in_flight:  response.attributes["ApproximateNumberOfMessagesNotVisible"].to_i
    }
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
        entries: entries
      )
    end
  end

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
