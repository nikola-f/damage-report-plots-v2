# frozen_string_literal: true

module AuthHelpers
  # Test user data constants
  TEST_USER_ID      = "12345"
  TEST_USER_EMAIL   = "test@example.com"
  TEST_USER_NAME    = "Test User"
  TEST_USER_PICTURE = "https://example.com/pic.jpg"

  def test_user_id    = TEST_USER_ID
  def test_user_email = TEST_USER_EMAIL
  def test_user_name  = TEST_USER_NAME
  def test_user_picture = TEST_USER_PICTURE

  def login_as(uid: TEST_USER_ID, email: TEST_USER_EMAIL, name: TEST_USER_NAME)
    mock_google_oauth_success(uid:, email:, name:)
    get "/auth/google_oauth2/callback"
  end

  def mock_google_oauth_success(overrides = {})
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
                                                                         provider: "google_oauth2",
                                                                         uid:      overrides[:uid] || TEST_USER_ID,
                                                                         info: {
                                                                           email: overrides[:email] || TEST_USER_EMAIL,
                                                                           name:  overrides[:name]  || TEST_USER_NAME,
                                                                           image: overrides[:picture] || TEST_USER_PICTURE
                                                                         },
                                                                         credentials: {
                                                                           token:      overrides[:google_token] || "google_access_token_123",
                                                                           expires_at: overrides[:expires_at]   || 1.hour.from_now.to_i
                                                                         }
                                                                       })
  end

  def mock_google_oauth_failure(_message = "invalid_credentials")
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    OmniAuth.config.on_failure = proc { |env|
      SessionsController.action(:failure).call(env)
    }
  end
end
