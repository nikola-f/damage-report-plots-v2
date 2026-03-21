module AuthHelpers
  # Test secrets
  TEST_JWT_SECRET = 'test_secret_key'.freeze

  # Test user data constants
  TEST_USER_ID = '12345'.freeze
  TEST_USER_EMAIL = 'test@example.com'.freeze
  TEST_USER_NAME = 'Test User'.freeze
  TEST_USER_PICTURE = 'https://example.com/pic.jpg'.freeze

  def test_user_id
    TEST_USER_ID
  end

  def test_user_email
    TEST_USER_EMAIL
  end

  def test_user_name
    TEST_USER_NAME
  end

  def test_user_picture
    TEST_USER_PICTURE
  end

  def mock_jwt_credentials
    allow(Rails.application.credentials).to receive(:jwt_secret_key!).and_return(TEST_JWT_SECRET)
  end

  def test_user_payload(overrides = {})
    {
      sub: TEST_USER_ID,
      email: TEST_USER_EMAIL,
      name: TEST_USER_NAME,
      picture: TEST_USER_PICTURE
    }.merge(overrides)
  end

  def generate_access_token(payload = {})
    JsonWebToken.encode(test_user_payload(payload))
  end

  def generate_expired_access_token(payload = {})
    JsonWebToken.encode(test_user_payload(payload), 1.second.ago)
  end

  def mock_google_oauth_success(overrides = {})
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      provider: 'google_oauth2',
      uid: overrides[:uid] || TEST_USER_ID,
      info: {
        email: overrides[:email] || TEST_USER_EMAIL,
        name: overrides[:name] || TEST_USER_NAME,
        image: overrides[:picture] || TEST_USER_PICTURE
      },
      credentials: {
        token: overrides[:google_token] || 'google_access_token_123',
        refresh_token: overrides[:google_refresh_token] || 'google_refresh_token_456',
        expires_at: overrides[:expires_at] || 1.hour.from_now.to_i
      }
    })
  end

  def mock_google_oauth_failure(message = 'invalid_credentials')
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    OmniAuth.config.on_failure = proc { |env|
      SessionsController.action(:failure).call(env)
    }
  end
end
