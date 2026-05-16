# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV["GOOGLE_CLIENT_ID"],
           ENV["GOOGLE_CLIENT_SECRET"],
           {
             scope: SessionsController::LOGIN_SCOPE,
             prompt: 'select_account',
             image_aspect_ratio: 'square',
             image_size: 50,
             access_type: 'online',
             include_granted_scopes: true,
             setup: proc { |env|
               if (scope = env['rack.session']['requested_scope'])
                 env['omniauth.strategy'].options[:scope] = scope
               end
             }
           }
end

# Allow GET for OAuth initiation from SPA (CSRF risk is low; state param handles it at Google's side)
OmniAuth.config.allowed_request_methods = %i[get post]

# Handle failures
OmniAuth.config.on_failure = proc { |env|
  SessionsController.action(:failure).call(env)
}
