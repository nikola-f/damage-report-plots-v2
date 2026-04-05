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

  describe "#extract_node" do
    let(:html) do
      "<ul><li><span>Title</span><a href=\"https://example.com\">Link</a></li><li><span>Other</span><a href=\"https://other.com\">Other</a></li></ul>"
    end
    subject(:decoder) { described_class.new(encode(html)) }

    context "when xpath matches a node" do
      it "returns the block result" do
        result = decoder.extract_node("//li[1]") do |node|
          [node.extract("span"), node.extract("a", attr: "href")]
        end
        expect(result).to eq(["Title", "https://example.com"])
      end
    end

    context "when xpath matches multiple nodes" do
      it "returns block result for the first match only" do
        result = decoder.extract_node("//li") { |node| node.extract("span") }
        expect(result).to eq("Title")
      end
    end

    context "when xpath does not match" do
      it "returns nil" do
        result = decoder.extract_node("//nonexistent") { |node| node.extract("span") }
        expect(result).to be_nil
      end
    end

    context "with invalid xpath" do
      it "raises ParseError" do
        expect { decoder.extract_node("[invalid xpath") { |node| node.extract("span") } }
          .to raise_error(EmailHtmlDecoder::ParseError)
      end
    end

    context "with invalid xpath inside block" do
      it "raises ParseError" do
        expect { decoder.extract_node("//li[1]") { |node| node.extract("[invalid") } }
          .to raise_error(EmailHtmlDecoder::ParseError)
      end
    end
  end

  describe "#extract_nodes" do
    let(:html) { "<ul><li><span>Apple</span><a href=\"https://a.com\">A</a></li><li><span>Banana</span><a href=\"https://b.com\">B</a></li></ul>" }
    subject(:decoder) { described_class.new(encode(html)) }

    context "when xpath matches nodes" do
      it "returns array of block results" do
        result = decoder.extract_nodes("//li") do |node|
          [node.extract("span"), node.extract("a", attr: "href")]
        end
        expect(result).to eq([
                               ["Apple", "https://a.com"],
                               ["Banana", "https://b.com"]
                             ])
      end
    end

    context "when xpath does not match" do
      it "returns empty array" do
        result = decoder.extract_nodes("//nonexistent") { |node| node.extract("span") }
        expect(result).to eq([])
      end
    end

    context "with invalid xpath" do
      it "raises ParseError" do
        expect { decoder.extract_nodes("[invalid xpath") { |node| node.extract("span") } }
          .to raise_error(EmailHtmlDecoder::ParseError)
      end
    end
  end

  describe "#extract_portals" do
    subject(:decoder) { described_class.new(file_fixture("sample_email_base64_urlsafe.txt").read) }

    it "returns an array of PortalRecord objects" do
      expect(decoder.extract_portals).to all(be_a(PortalRecord))
    end

    it "extracts portal name, intel URL, and owned for each portal" do
      result = decoder.extract_portals

      expect(result).to eq([
                             PortalRecord.new(
                               name:      "ハチ公",
                               latitude:  "35.659054",
                               longitude: "139.700583",
                               owned:     false
                             ),
                             PortalRecord.new(
                               name:      "海からのかおり",
                               latitude:  "35.659113",
                               longitude: "139.701690",
                               owned:     false
                             )
                           ])
    end
  end

  describe "#extract_all" do
    let(:html) { "<ul><li>Apple</li><li>Banana</li><li>Cherry</li></ul>" }
    subject(:decoder) { described_class.new(encode(html)) }

    context "when xpath matches nodes" do
      it "returns text content of all matching nodes" do
        expect(decoder.extract_all("//li")).to eq(%w[Apple Banana Cherry])
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
