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

  class DecodeError < StandardError; end
  class ParseError < StandardError; end

  private

  def validate!(str)
    raise ArgumentError, "encoded_html must not be nil or empty" if str.nil? || str.empty?
    raise DecodeError, "invalid character in base64" unless str.match?(/\A[A-Za-z0-9\-_=]*\z/)
  end
end
