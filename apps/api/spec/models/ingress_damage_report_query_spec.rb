# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngressDamageReportQuery do
  let(:from_query) do
    "{from:ingress-support@google.com from:ingress-support@nianticlabs.com " \
      "from:ingress-support@nianticspatial.com}"
  end

  describe "#to_s" do
    it "builds the query with fixed subject, from, smaller, and date range" do
      query = described_class.new(after_date: "2024-01-01")
      expect(query.to_s).to eq(
        "subject:Ingress Damage Report: Entities attacked by " \
        "after:2024/01/01 before:2027/01/01 " \
        "#{from_query} " \
        "smaller:100K"
      )
    end

    it "handles leap year correctly (2024-02-29 + 3 years = 2027-02-28)" do
      query = described_class.new(after_date: "2024-02-29")
      expect(query.to_s).to eq(
        "subject:Ingress Damage Report: Entities attacked by " \
        "after:2024/02/29 before:2027/02/28 " \
        "#{from_query} " \
        "smaller:100K"
      )
    end

    it "defaults after_date to 2012-10-15 when nil" do
      query = described_class.new
      expect(query.to_s).to eq(
        "subject:Ingress Damage Report: Entities attacked by " \
        "after:2012/10/15 before:2015/10/15 " \
        "#{from_query} " \
        "smaller:100K"
      )
    end
  end
end
