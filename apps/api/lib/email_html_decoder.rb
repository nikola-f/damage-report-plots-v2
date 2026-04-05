# frozen_string_literal: true

require "base64"
require "nokogiri"

class EmailHtmlDecoder
  def initialize(encoded_html)
    validate!(encoded_html)
    html = begin
      Base64.urlsafe_decode64(encoded_html).force_encoding("UTF-8")
    rescue ArgumentError => e
      raise DecodeError, "Failed to decode HTML: #{e.message}"
    end
    @doc = Nokogiri::HTML(html)
  end

  PORTAL_XPATH = "//tbody/tr/td[div/a[contains(@href,'ingress.com/intel')]]"

  # Extracts all attacked portals from an Ingress damage report email.
  # @return [Array<PortalRecord>]
  def extract_portals
    agent_name = extract("//span[contains(text(),'Agent Name:')]/following-sibling::span[1]")
    extract_nodes(PORTAL_XPATH) do |node|
      owner = node.extract("../following-sibling::tr[2]/td/table/td[2]/div")
                  &.split("Owner: ", 2)&.last
      PortalRecord.new(
        name:      node.extract("div[1]"),
        intel_url: node.extract("div[2]/a", attr: "href"),
        owned:     agent_name == owner
      )
    end
  end

  def extract(xpath, attr: nil)
    node = @doc.xpath(xpath).first
    return nil if node.nil?

    attr ? node[attr] : node.xpath("text()").map(&:text).join
  rescue Nokogiri::XML::XPath::SyntaxError => e
    raise ParseError, "Invalid XPath expression: #{e.message}"
  end

  def extract_all(xpath, attr: nil)
    @doc.xpath(xpath).map do |node|
      attr ? node[attr] : node.xpath("text()").map(&:text).join
    end
  rescue Nokogiri::XML::XPath::SyntaxError => e
    raise ParseError, "Invalid XPath expression: #{e.message}"
  end

  def extract_node(xpath, &block)
    node = @doc.xpath(xpath).first
    return nil if node.nil?

    block.call(Node.new(node))
  rescue Nokogiri::XML::XPath::SyntaxError => e
    raise ParseError, "Invalid XPath expression: #{e.message}"
  end

  def extract_nodes(xpath, &block)
    @doc.xpath(xpath).map { |n| block.call(Node.new(n)) }
  rescue Nokogiri::XML::XPath::SyntaxError => e
    raise ParseError, "Invalid XPath expression: #{e.message}"
  end

  class DecodeError < StandardError; end
  class ParseError < StandardError; end

  class Node
    def initialize(node)
      @node = node
    end

    def extract(xpath, attr: nil)
      child = @node.xpath(xpath).first
      return nil if child.nil?

      attr ? child[attr] : child.xpath("text()").map(&:text).join
    rescue Nokogiri::XML::XPath::SyntaxError => e
      raise EmailHtmlDecoder::ParseError, "Invalid XPath expression: #{e.message}"
    end

    def extract_all(xpath, attr: nil)
      @node.xpath(xpath).map do |child|
        attr ? child[attr] : child.xpath("text()").map(&:text).join
      end
    rescue Nokogiri::XML::XPath::SyntaxError => e
      raise EmailHtmlDecoder::ParseError, "Invalid XPath expression: #{e.message}"
    end
  end
  private_constant :Node

  private

  def validate!(str)
    raise ArgumentError, "encoded_html must not be nil or empty" if str.nil? || str.empty?
    raise DecodeError, "invalid character in base64" unless str.match?(/\A[A-Za-z0-9\-_=]*\z/)
  end
end
