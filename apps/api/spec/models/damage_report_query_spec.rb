# frozen_string_literal: true

require "rails_helper"

RSpec.describe DamageReportQuery do
  let(:from_query) do
    "{from:ingress-support@google.com from:ingress-support@nianticlabs.com " \
      "from:ingress-support@nianticspatial.com}"
  end

  describe "#to_s" do
    it "builds the query with fixed subject, from, smaller, and date range" do
      query = described_class.new(after_date: Time.utc(2024, 1, 1).to_i)
      expect(query.to_s).to eq(
        "subject:Ingress Damage Report: Entities attacked by " \
        "after:#{Time.utc(2024, 1, 1).to_i} before:#{Time.utc(2027, 1, 1).to_i} " \
        "#{from_query} " \
        "larger:5K smaller:100K"
      )
    end

    it "handles leap year correctly (2024-02-29 + 3 years = 2027-02-28)" do
      query = described_class.new(after_date: Time.utc(2024, 2, 29).to_i)
      expect(query.to_s).to eq(
        "subject:Ingress Damage Report: Entities attacked by " \
        "after:#{Time.utc(2024, 2, 29).to_i} before:#{Time.utc(2027, 2, 28).to_i} " \
        "#{from_query} " \
        "larger:5K smaller:100K"
      )
    end

    it "defaults after_date to 2012-10-15 when nil" do
      query = described_class.new
      expect(query.to_s).to eq(
        "subject:Ingress Damage Report: Entities attacked by " \
        "after:#{Time.utc(2012, 10, 15).to_i} before:#{Time.utc(2015, 10, 15).to_i} " \
        "#{from_query} " \
        "larger:5K smaller:100K"
      )
    end
  end
end
