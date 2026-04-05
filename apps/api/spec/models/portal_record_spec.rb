# frozen_string_literal: true

require "rails_helper"

RSpec.describe PortalRecord do
  subject(:record) do
    described_class.new(
      name:      "ハチ公",
      latitude:  "35.659054",
      longitude: "139.700583",
      owned:     false
    )
  end

  it { expect(record.name).to eq("ハチ公") }
  it { expect(record.latitude).to eq("35.659054") }
  it { expect(record.longitude).to eq("139.700583") }
  it { expect(record).to be_frozen }

  describe "#owned" do
    it "returns true when owned is true" do
      record = described_class.new(name: "P", latitude: "0", longitude: "0", owned: true)
      expect(record.owned).to be true
    end

    it "returns false when owned is false" do
      record = described_class.new(name: "P", latitude: "0", longitude: "0", owned: false)
      expect(record.owned).to be false
    end
  end
end
