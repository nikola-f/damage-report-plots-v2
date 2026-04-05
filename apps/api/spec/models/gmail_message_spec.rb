# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailMessage do
  let(:html_part)  { { "mimeType" => "text/html",  "body" => { "data" => "html_data" } } }
  let(:plain_part) { { "mimeType" => "text/plain", "body" => { "data" => "plain_data" } } }

  describe "#id and #internal_date" do
    let(:raw) { { "id" => "msg_1", "internalDate" => "1700000000000", "payload" => {} } }

    it "exposes id" do
      expect(described_class.new(raw).id).to eq("msg_1")
    end

    it "exposes internal_date" do
      expect(described_class.new(raw).internal_date).to eq("1700000000000")
    end
  end

  describe "#html_body_data" do
    context "when parts contain both text/html and text/plain" do
      let(:raw) do
        { "id" => "m1", "internalDate" => "0",
          "payload" => { "parts" => [plain_part, html_part] } }
      end

      it "returns only the text/html body data" do
        expect(described_class.new(raw).html_body_data).to eq(["html_data"])
      end
    end

    context "when there are multiple text/html parts" do
      let(:html_part2) { { "mimeType" => "text/html", "body" => { "data" => "html_data_2" } } }
      let(:raw) do
        { "id" => "m1", "internalDate" => "0",
          "payload" => { "parts" => [html_part, html_part2] } }
      end

      it "returns data from all text/html parts" do
        expect(described_class.new(raw).html_body_data).to eq(%w[html_data html_data_2])
      end
    end

    context "when there are no text/html parts" do
      let(:raw) do
        { "id" => "m1", "internalDate" => "0",
          "payload" => { "parts" => [plain_part] } }
      end

      it "returns an empty array" do
        expect(described_class.new(raw).html_body_data).to eq([])
      end
    end

    context "when payload has no parts key" do
      let(:raw) { { "id" => "m1", "internalDate" => "0", "payload" => {} } }

      it "returns an empty array" do
        expect(described_class.new(raw).html_body_data).to eq([])
      end
    end
  end

  describe "#html_decoders" do
    let(:decoder) { instance_double(EmailHtmlDecoder) }

    before { allow(EmailHtmlDecoder).to receive(:new).and_return(decoder) }

    context "when there is one text/html part" do
      let(:raw) do
        { "id" => "m1", "internalDate" => "0",
          "payload" => { "parts" => [html_part] } }
      end

      it "returns an array of EmailHtmlDecoder instances" do
        result = described_class.new(raw).html_decoders
        expect(result).to eq([decoder])
      end

      it "initializes EmailHtmlDecoder with the body data" do
        described_class.new(raw).html_decoders
        expect(EmailHtmlDecoder).to have_received(:new).with("html_data")
      end
    end

    context "when there are no text/html parts" do
      let(:raw) { { "id" => "m1", "internalDate" => "0", "payload" => {} } }

      it "returns an empty array" do
        expect(described_class.new(raw).html_decoders).to eq([])
      end
    end
  end
end
