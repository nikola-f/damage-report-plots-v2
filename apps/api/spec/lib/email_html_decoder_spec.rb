# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailHtmlDecoder do
  describe '.decode' do
    context 'with standard base64' do
      it 'decodes an HTML string' do
        html = '<html><body><p>Hello</p></body></html>'
        encoded = Base64.strict_encode64(html)

        expect(described_class.decode(encoded)).to eq(html)
      end

      it 'decodes base64 with newlines (email format)' do
        html = '<html><body><p>Hello</p></body></html>'
        encoded = Base64.encode64(html) # includes newlines every 60 chars

        expect(described_class.decode(encoded)).to eq(html)
      end
    end

    context 'with URL-safe base64' do
      it 'decodes URL-safe base64 with padding' do
        html = '<html><body><p>Hello</p></body></html>'
        encoded = Base64.urlsafe_encode64(html)

        expect(described_class.decode(encoded)).to eq(html)
      end

      it 'decodes URL-safe base64 without padding' do
        html = '<html><body><p>Hello</p></body></html>'
        encoded = Base64.urlsafe_encode64(html, padding: false)

        expect(described_class.decode(encoded)).to eq(html)
      end
    end

    context 'with Japanese HTML (UTF-8)' do
      it 'decodes and returns a UTF-8 string' do
        html = '<html><body><p>こんにちは</p></body></html>'
        encoded = Base64.strict_encode64(html)

        result = described_class.decode(encoded)
        expect(result).to eq(html)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with invalid input' do
      it 'raises DecodeError for invalid base64' do
        expect { described_class.decode("!!!invalid!!!") }.to raise_error(EmailHtmlDecoder::DecodeError)
      end
    end
  end
end
