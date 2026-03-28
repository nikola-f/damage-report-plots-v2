require "base64"

class EmailHtmlDecoder
  def self.decode(encoded_html)
    validate!(encoded_html)
    Base64.urlsafe_decode64(encoded_html).force_encoding("UTF-8")
  rescue ArgumentError => e
    raise DecodeError, "Failed to decode HTML: #{e.message}"
  end

  class DecodeError < StandardError; end

  private_class_method def self.validate!(str)
    raise ArgumentError, "invalid character in base64" unless str.match?(/\A[A-Za-z0-9\-_=]*\z/)
  end
end
