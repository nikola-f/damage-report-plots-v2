# frozen_string_literal: true

require "rails_helper"

RSpec.describe DamageReportRecord do
  subject(:record) do
    described_class.new(
      name:          "ハチ公",
      latitude:      "35.659054",
      longitude:     "139.700583",
      owned:         false,
      internal_date: "1700000000000"
    )
  end

  it { expect(record.name).to eq("ハチ公") }
  it { expect(record.latitude).to eq("35.659054") }
  it { expect(record.longitude).to eq("139.700583") }
  it { expect(record.internal_date).to eq("1700000000000") }
  it { expect(record).to be_frozen }

  describe "#portal_id" do
    it "returns a non-empty string" do
      expect(record.portal_id).to be_a(String).and(be_present)
    end

    it "is deterministic for the same coordinates" do
      expect(record.portal_id).to eq(record.portal_id)
    end

    it "differs for different coordinates" do
      other = described_class.new(name: "渋谷ヒカリエ", latitude: "35.659000", longitude: "139.700583", owned: false, internal_date: nil)
      expect(record.portal_id).not_to eq(other.portal_id)
    end
  end

  describe "#owned" do
    it "returns true when owned is true" do
      record = described_class.new(name: "P", latitude: "0", longitude: "0", owned: true, internal_date: nil)
      expect(record.owned).to be true
    end

    it "returns false when owned is false" do
      record = described_class.new(name: "P", latitude: "0", longitude: "0", owned: false, internal_date: nil)
      expect(record.owned).to be false
    end
  end

  describe ".deduplicate" do
    let(:base) { { name: "P", latitude: "35.0", longitude: "139.0", internal_date: "1000" } }

    it "returns a single record when given one" do
      r = described_class.new(**base, owned: false)
      expect(described_class.deduplicate([r])).to eq([r])
    end

    it "deduplicates on name/latitude/longitude/internal_date (ignoring owned)" do
      r1 = described_class.new(**base, owned: false)
      r2 = described_class.new(**base, owned: true)
      expect(described_class.deduplicate([r1, r2]).size).to eq(1)
    end

    it "keeps owned:true when both owned:false and owned:true are present" do
      r_false = described_class.new(**base, owned: false)
      r_true  = described_class.new(**base, owned: true)
      expect(described_class.deduplicate([r_false, r_true])).to eq([r_true])
    end

    it "keeps owned:true regardless of order" do
      r_false = described_class.new(**base, owned: false)
      r_true  = described_class.new(**base, owned: true)
      expect(described_class.deduplicate([r_true, r_false])).to eq([r_true])
    end

    it "keeps one record when all are owned:false" do
      r1 = described_class.new(**base, owned: false)
      r2 = described_class.new(**base, owned: false)
      expect(described_class.deduplicate([r1, r2]).size).to eq(1)
    end
  end
end
