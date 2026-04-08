# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpreadsheetTemplate do
  let(:sheet)    { SpreadsheetTemplate::Sheet.new(name: "Attacks", headers: %w[Date Portal]) }
  let(:template) { described_class.new(sheets: [sheet]) }

  it "is frozen" do
    expect(template).to be_frozen
  end

  it "exposes sheets" do
    expect(template.sheets).to eq([sheet])
  end

  it "converts to hash" do
    expect(template.to_h).to eq({ sheets: [sheet] })
  end

  describe "SpreadsheetTemplate::Sheet" do
    it "is frozen" do
      expect(sheet).to be_frozen
    end

    it "exposes name and headers" do
      expect(sheet.name).to eq("Attacks")
      expect(sheet.headers).to eq(%w[Date Portal])
    end

    it "converts to hash" do
      expect(sheet.to_h).to eq({ name: "Attacks", headers: %w[Date Portal] })
    end
  end
end
