# frozen_string_literal: true

require "rails_helper"
require "base64"

RSpec.describe EmailHtmlDecoder do
  def encode(html)
    Base64.urlsafe_encode64(html)
  end

  describe ".new" do
    context "with valid encoded HTML" do
      it "creates an instance without error" do
        expect { described_class.new(encode("<div>hello</div>")) }.not_to raise_error
      end
    end

    context "with nil" do
      it "raises ArgumentError" do
        expect { described_class.new(nil) }.to raise_error(ArgumentError)
      end
    end

    context "with empty string" do
      it "raises ArgumentError" do
        expect { described_class.new("") }.to raise_error(ArgumentError)
      end
    end

    context "with invalid base64 characters" do
      it "raises DecodeError" do
        expect { described_class.new("!!!invalid!!!") }.to raise_error(EmailHtmlDecoder::DecodeError)
      end
    end
  end

  describe "#extract" do
    let(:html) { "<div><p class=\"title\">Hello</p><p class=\"body\">World <span>!</span></p></div>" }
    subject(:decoder) { described_class.new(encode(html)) }

    context "when xpath matches a node" do
      it "returns the direct text content of the first match" do
        expect(decoder.extract('//p[@class="title"]')).to eq("Hello")
      end
    end

    context "when xpath matches multiple nodes" do
      it "returns only the first match" do
        expect(decoder.extract("//p")).to eq("Hello")
      end
    end

    context "with direct text nodes only" do
      it "does not include text from descendant elements" do
        expect(decoder.extract('//p[@class="body"]')).to eq("World ")
      end
    end

    context "when xpath does not match" do
      it "returns nil" do
        expect(decoder.extract("//nonexistent")).to be_nil
      end
    end

    context "with attr option" do
      let(:html) { "<div><a href=\"https://example.com\">Link</a></div>" }

      it "returns the attribute value of the first match" do
        expect(decoder.extract("//a", attr: "href")).to eq("https://example.com")
      end
    end

    context "with invalid xpath" do
      it "raises ParseError" do
        expect { decoder.extract("[invalid xpath") }.to raise_error(EmailHtmlDecoder::ParseError)
      end
    end
  end

  describe "#extract_all" do
    let(:html) { "<ul><li>Apple</li><li>Banana</li><li>Cherry</li></ul>" }
    subject(:decoder) { described_class.new(encode(html)) }

    context "when xpath matches nodes" do
      it "returns text content of all matching nodes" do
        expect(decoder.extract_all("//li")).to eq(["Apple", "Banana", "Cherry"])
      end
    end

    context "when xpath does not match" do
      it "returns empty array" do
        expect(decoder.extract_all("//nonexistent")).to eq([])
      end
    end

    context "with attr option" do
      let(:html) { "<ul><li><a href=\"https://a.com\">A</a></li><li><a href=\"https://b.com\">B</a></li></ul>" }

      it "returns attribute values of all matching nodes" do
        expect(decoder.extract_all("//a", attr: "href")).to eq(["https://a.com", "https://b.com"])
      end
    end

    context "with invalid xpath" do
      it "raises ParseError" do
        expect { decoder.extract_all("[invalid xpath") }.to raise_error(EmailHtmlDecoder::ParseError)
      end
    end
  end
end
