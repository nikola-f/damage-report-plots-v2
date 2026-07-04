# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserIdMasking do
  let(:masker) do
    Class.new do
      include UserIdMasking
    end.new
  end

  describe "#masked_user_id" do
    it "keeps only a short prefix of the Google account ID" do
      expect(masker.masked_user_id("12345678901234567")).to eq("1234***")
    end

    it "handles ids shorter than the visible prefix" do
      expect(masker.masked_user_id("12")).to eq("12***")
    end

    it "handles nil" do
      expect(masker.masked_user_id(nil)).to eq("***")
    end
  end
end
