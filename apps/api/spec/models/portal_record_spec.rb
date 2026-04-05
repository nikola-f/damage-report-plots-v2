# frozen_string_literal: true

require "rails_helper"

RSpec.describe PortalRecord do
  subject(:record) do
    described_class.new(
      name:       "ハチ公",
      intel_url:  "https://www.ingress.com/intel?ll=35.659054,139.700583",
      agent_name: "AgentSmith",
      damage:     "DAMAGE:1 Resonator destroyed",
      status:     "STATUS:Level 1Health: 0%Owner: [uncaptured]"
    )
  end

  it { expect(record.name).to eq("ハチ公") }
  it { expect(record.intel_url).to eq("https://www.ingress.com/intel?ll=35.659054,139.700583") }
  it { expect(record.agent_name).to eq("AgentSmith") }
  it { expect(record.damage).to eq("DAMAGE:1 Resonator destroyed") }
  it { expect(record.status).to eq("STATUS:Level 1Health: 0%Owner: [uncaptured]") }
  it { expect(record).to be_frozen }
end
