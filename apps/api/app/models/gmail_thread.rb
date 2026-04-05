# frozen_string_literal: true

# Wraps a Gmail thread from the threads.get API response.
class GmailThread
  attr_reader :id, :messages

  def initialize(raw)
    @id       = raw["id"]
    @messages = (raw["messages"] || []).map { |m| GmailMessage.new(m) }
  end
end
