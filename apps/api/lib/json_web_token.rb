# frozen_string_literal: true

class JsonWebToken
  ALGORITHM = 'HS256'

  class << self
    def encode(payload, exp = 15.minutes.from_now)
      payload[:exp] = exp.to_i
      payload[:iat] = Time.now.to_i
      payload[:iss] = 'damage-report-api'

      JWT.encode(payload, secret_key, ALGORITHM)
    end

    def decode(token)
      decoded = JWT.decode(
        token,
        secret_key,
        true,
        { algorithm: ALGORITHM }
      )[0]

      HashWithIndifferentAccess.new(decoded)
    rescue JWT::ExpiredSignature => e
      raise JWT::ExpiredSignature, e.message
    rescue JWT::DecodeError => e
      raise JWT::DecodeError, e.message
    end

    def encode_refresh_token(payload, exp = 7.days.from_now)
      payload[:exp] = exp.to_i
      payload[:iat] = Time.now.to_i
      payload[:type] = 'refresh'

      JWT.encode(payload, refresh_secret_key, ALGORITHM)
    end

    def decode_refresh_token(token)
      decoded = JWT.decode(
        token,
        refresh_secret_key,
        true,
        { algorithm: ALGORITHM }
      )[0]

      HashWithIndifferentAccess.new(decoded)
    rescue JWT::ExpiredSignature => e
      raise JWT::ExpiredSignature, e.message
    rescue JWT::DecodeError => e
      raise JWT::DecodeError, e.message
    end

    private

    def secret_key
      Rails.application.credentials.jwt_secret_key!
    end

    def refresh_secret_key
      Rails.application.credentials.jwt_refresh_secret!
    end
  end
end
