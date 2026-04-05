# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailThread do
  describe "#id" do
    it "exposes the thread id" do
      thread = described_class.new({ "id" => "thread_1", "messages" => [] })
      expect(thread.id).to eq("thread_1")
    end
  end

  describe "#messages" do
    it "returns an array of GmailMessage objects" do
      raw = {
        "id" => "thread_1",
        "messages" => [
          { "id" => "msg_1", "internalDate" => "1000", "payload" => {} },
          { "id" => "msg_2", "internalDate" => "2000", "payload" => {} }
        ]
      }
      messages = described_class.new(raw).messages
      expect(messages).to all(be_a(GmailMessage))
      expect(messages.map(&:id)).to eq(%w[msg_1 msg_2])
    end

    context "when messages key is absent" do
      it "returns an empty array" do
        expect(described_class.new({ "id" => "t1" }).messages).to eq([])
      end
    end
  end
end
