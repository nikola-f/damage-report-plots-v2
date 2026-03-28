# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailHtmlDecoder do
  describe '.decode' do
    context 'with URL-safe base64 with padding' do
      it 'decodes an HTML string' do
        html = file_fixture("sample_email.html").read
        encoded = file_fixture("sample_email_base64_urlsafe.txt").read

        expect(described_class.decode(encoded)).to eq(html)
      end
    end

    context 'with invalid input' do
      it 'raises DecodeError for invalid base64' do
        expect { described_class.decode("!!!invalid!!!") }.to raise_error(EmailHtmlDecoder::DecodeError)
      end
    end
  end
end
