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
  # @param internal_date [String, nil] internalDate from the Gmail message
  # @return [Array<DamageReportRecord>]
  def extract_portals(internal_date: nil)
    truncated_date = internal_date && internal_date.to_i / 86_400_000 * 864
    agent_name = extract("//span[contains(text(),'Agent Name:')]/following-sibling::span[1]")&.strip
    Rails.logger.debug { "extract_portals: agent_name=#{agent_name.inspect}" }
    extract_nodes(PORTAL_XPATH) do |node|
      owner     = node.extract("../following-sibling::tr[2]//div[contains(.,'Owner:')]", inner_text: true)
                      &.split("Owner: ", 2)&.last&.strip
      intel_url = node.extract("div[2]/a", attr: "href")
      pll       = intel_url&.match(/[?&]pll=([^&]+)/)&.[](1)
      lat, lng  = pll&.split(",")
      name      = node.extract("div[1]")
      Rails.logger.debug { "extract_portals: portal=#{name.inspect} owner=#{owner.inspect} owned=#{agent_name == owner}" }
      DamageReportRecord.new(
        name:          name,
        latitude:      lat,
        longitude:     lng,
        owned:         agent_name == owner,
        internal_date: truncated_date
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

    def extract(xpath, attr: nil, inner_text: false)
      child = @node.xpath(xpath).first
      return nil if child.nil?

      if attr
        child[attr]
      elsif inner_text
        child.text
      else
        child.xpath("text()").map(&:text).join
      end
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
