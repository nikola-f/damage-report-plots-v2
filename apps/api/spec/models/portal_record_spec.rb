# frozen_string_literal: true

require "rails_helper"

RSpec.describe PortalRecord do
  subject(:record) do
    described_class.new(
      name:      "ハチ公",
      intel_url: "https://www.ingress.com/intel?ll=35.659054,139.700583",
      owned:     false
    )
  end

  it { expect(record.name).to eq("ハチ公") }
  it { expect(record.intel_url).to eq("https://www.ingress.com/intel?ll=35.659054,139.700583") }
  it { expect(record).to be_frozen }

  describe "#owned?" do
    context "when owned is true" do
      subject { described_class.new(name: "P", intel_url: "u", owned: true) }

      it { is_expected.to be_owned }
    end

    context "when owned is false" do
      subject { described_class.new(name: "P", intel_url: "u", owned: false) }

      it { is_expected.not_to be_owned }
    end
  end
end
