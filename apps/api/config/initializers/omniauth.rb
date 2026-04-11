# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           Rails.application.credentials.dig(:google, :client_id),
           Rails.application.credentials.dig(:google, :client_secret),
           {
             scope: 'email,profile',
             prompt: 'select_account',
             image_aspect_ratio: 'square',
             image_size: 50,
             access_type: 'online',
             include_granted_scopes: true
           }
end

# Security: protect against CSRF
OmniAuth.config.allowed_request_methods = %i[post get]

# Handle failures
OmniAuth.config.on_failure = proc { |env|
  SessionsController.action(:failure).call(env)
}
