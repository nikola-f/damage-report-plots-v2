# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailSearchQuery do
  describe "#to_s" do
    context "when all fields are nil / empty" do
      it "returns nil" do
        expect(described_class.new.to_s).to be_nil
      end
    end

    context "with subject only" do
      it "returns subject: query" do
        query = described_class.new(subject: "damage report")
        expect(query.to_s).to eq("subject:damage report")
      end
    end

    context "with after_date only" do
      it "returns after: query as Unix epoch" do
        query = described_class.new(after_date: Time.utc(2024, 1, 1).to_i)
        expect(query.to_s).to eq("after:#{Time.utc(2024, 1, 1).to_i}")
      end
    end

    context "with before_date only" do
      it "returns before: query as Unix epoch" do
        query = described_class.new(before_date: Time.utc(2024, 12, 31).to_i)
        expect(query.to_s).to eq("before:#{Time.utc(2024, 12, 31).to_i}")
      end
    end

    context "with a single from address" do
      it "returns from: query without braces" do
        query = described_class.new(from: ["sender@example.com"])
        expect(query.to_s).to eq("from:sender@example.com")
      end
    end

    context "with multiple from addresses" do
      it "returns OR query with braces" do
        query = described_class.new(from: ["a@example.com", "b@example.com"])
        expect(query.to_s).to eq("{from:a@example.com from:b@example.com}")
      end
    end

    context "with smaller only" do
      it "returns smaller: query" do
        query = described_class.new(smaller: "10m")
        expect(query.to_s).to eq("smaller:10m")
      end
    end

    context "with all fields specified" do
      it "returns all criteria joined by space in order" do
        query = described_class.new(
          subject:     "damage report",
          after_date:  Time.utc(2024, 1, 1).to_i,
          before_date: Time.utc(2024, 12, 31).to_i,
          from:        ["a@example.com", "b@example.com"],
          smaller:     "10m"
        )
        expect(query.to_s).to eq(
          "subject:damage report after:#{Time.utc(2024, 1, 1).to_i} before:#{Time.utc(2024, 12, 31).to_i} " \
          "{from:a@example.com from:b@example.com} smaller:10m"
        )
      end
    end

    context "with a subset of fields" do
      it "omits nil fields" do
        query = described_class.new(subject: "report", smaller: "5m")
        expect(query.to_s).to eq("subject:report smaller:5m")
      end
    end
  end

  describe "immutability" do
    it "is frozen" do
      expect(described_class.new(subject: "test")).to be_frozen
    end
  end
end
