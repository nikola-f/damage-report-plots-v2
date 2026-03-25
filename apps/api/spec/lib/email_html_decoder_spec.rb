# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailHtmlDecoder do
  describe '.decode' do
    context 'with standard base64' do
      it 'decodes an HTML string' do
        html = file_fixture("sample_email.html").read
        encoded = file_fixture("sample_email_base64_strict.txt").read

        expect(described_class.decode(encoded)).to eq(html)
      end

      it 'decodes base64 with newlines (email format)' do
        html = file_fixture("sample_email.html").read
        encoded = file_fixture("sample_email_base64_email.txt").read

        expect(described_class.decode(encoded)).to eq(html)
      end
    end

    context 'with URL-safe base64' do
      it 'decodes URL-safe base64 with padding' do
        html = file_fixture("sample_email.html").read
        encoded = file_fixture("sample_email_base64_urlsafe.txt").read

        expect(described_class.decode(encoded, url_safe: true)).to eq(html)
      end

      it 'decodes URL-safe base64 without padding' do
        html = file_fixture("sample_email.html").read
        encoded = file_fixture("sample_email_base64_urlsafe_nopadding.txt").read

        expect(described_class.decode(encoded, url_safe: true)).to eq(html)
      end
    end

    context 'with Japanese HTML (UTF-8)' do
      it 'decodes and returns a UTF-8 string' do
        html = file_fixture("sample_email_japanese.html").read
        encoded = file_fixture("sample_email_japanese_base64_strict.txt").read

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
