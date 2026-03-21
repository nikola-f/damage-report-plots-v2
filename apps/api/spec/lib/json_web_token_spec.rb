# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JsonWebToken do
  let(:payload) { { sub: '12345', email: 'test@example.com', name: 'Test User' } }

  before do
    # Mock credentials
    allow(Rails.application.credentials).to receive(:jwt_secret_key!).and_return('test_secret_key')
    allow(Rails.application.credentials).to receive(:jwt_refresh_secret!).and_return('test_refresh_secret_key')
  end

  describe '.encode' do
    it 'encodes a payload into a JWT token' do
      token = described_class.encode(payload)
      expect(token).to be_a(String)
      expect(token.split('.').length).to eq(3)
    end

    it 'includes expiration time in the payload' do
      token = described_class.encode(payload)
      decoded = JWT.decode(token, 'test_secret_key', true, { algorithm: 'HS256' })[0]
      expect(decoded['exp']).to be_present
    end

    it 'includes issued at time in the payload' do
      token = described_class.encode(payload)
      decoded = JWT.decode(token, 'test_secret_key', true, { algorithm: 'HS256' })[0]
      expect(decoded['iat']).to be_present
    end

    it 'includes issuer in the payload' do
      token = described_class.encode(payload)
      decoded = JWT.decode(token, 'test_secret_key', true, { algorithm: 'HS256' })[0]
      expect(decoded['iss']).to eq('damage-report-api')
    end
  end

  describe '.decode' do
    it 'decodes a valid JWT token' do
      token = described_class.encode(payload)
      decoded = described_class.decode(token)
      expect(decoded['sub']).to eq('12345')
      expect(decoded['email']).to eq('test@example.com')
      expect(decoded['name']).to eq('Test User')
    end

    it 'raises JWT::DecodeError for invalid token' do
      expect { described_class.decode('invalid.token.here') }.to raise_error(JWT::DecodeError)
    end

    it 'raises JWT::ExpiredSignature for expired token' do
      token = described_class.encode(payload, 1.second.ago)
      expect { described_class.decode(token) }.to raise_error(JWT::ExpiredSignature)
    end
  end

  describe '.encode_refresh_token' do
    it 'encodes a refresh token' do
      token = described_class.encode_refresh_token(payload)
      expect(token).to be_a(String)
      expect(token.split('.').length).to eq(3)
    end

    it 'includes type refresh in the payload' do
      token = described_class.encode_refresh_token(payload)
      decoded = JWT.decode(token, 'test_refresh_secret_key', true, { algorithm: 'HS256' })[0]
      expect(decoded['type']).to eq('refresh')
    end
  end

  describe '.decode_refresh_token' do
    it 'decodes a valid refresh token' do
      token = described_class.encode_refresh_token(payload)
      decoded = described_class.decode_refresh_token(token)
      expect(decoded['sub']).to eq('12345')
      expect(decoded['type']).to eq('refresh')
    end

    it 'raises JWT::DecodeError for invalid refresh token' do
      expect { described_class.decode_refresh_token('invalid.token.here') }.to raise_error(JWT::DecodeError)
    end
  end
end
