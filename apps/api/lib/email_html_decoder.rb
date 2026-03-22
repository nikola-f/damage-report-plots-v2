require "base64"

class EmailHtmlDecoder
  def self.decode(encoded_html)
    if url_safe?(encoded_html)
      validate_url_safe!(encoded_html)
      Base64.urlsafe_decode64(pad(encoded_html)).force_encoding("UTF-8")
    else
      validate_standard!(encoded_html)
      Base64.decode64(encoded_html).force_encoding("UTF-8")
    end
  rescue ArgumentError => e
    raise DecodeError, "Failed to decode HTML: #{e.message}"
  end

  class DecodeError < StandardError; end

  private_class_method def self.url_safe?(str)
    str.match?(/[-_]/)
  end

  private_class_method def self.validate_standard!(str)
    raise ArgumentError, "invalid character in base64" unless str.match?(/\A[A-Za-z0-9+\/=\s]*\z/)
  end

  private_class_method def self.validate_url_safe!(str)
    raise ArgumentError, "invalid character in base64" unless str.match?(/\A[A-Za-z0-9\-_=\s]*\z/)
  end

  private_class_method def self.pad(str)
    str.gsub(/\s/, "").then { |s| s + "=" * ((4 - s.length % 4) % 4) }
  end
end
