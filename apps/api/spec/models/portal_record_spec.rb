# frozen_string_literal: true

require "rails_helper"

RSpec.describe PortalRecord do
  subject(:record) do
    described_class.new(
      name:       "ハチ公",
      intel_url:  "https://www.ingress.com/intel?ll=35.659054,139.700583",
      agent_name: "AgentSmith",
      damage:     "DAMAGE:1 Resonator destroyed",
      status:     "[uncaptured]"
    )
  end

  it { expect(record.name).to eq("ハチ公") }
  it { expect(record.intel_url).to eq("https://www.ingress.com/intel?ll=35.659054,139.700583") }
  it { expect(record.agent_name).to eq("AgentSmith") }
  it { expect(record.damage).to eq("DAMAGE:1 Resonator destroyed") }
  it { expect(record.status).to eq("[uncaptured]") }
  it { expect(record).to be_frozen }

  describe "#owned" do
    context "when agent_name matches status" do
      subject { described_class.new(name: "P", intel_url: "u", agent_name: "AgentX", damage: "d", status: "AgentX") }

      it { is_expected.to be_owned }
    end

    context "when agent_name does not match status" do
      subject { described_class.new(name: "P", intel_url: "u", agent_name: "AgentX", damage: "d", status: "[uncaptured]") }

      it { is_expected.not_to be_owned }
    end
  end
end
