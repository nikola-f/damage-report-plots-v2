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
               session  = env['rack.session']
               strategy = env['omniauth.strategy']
               if (scope = session['requested_scope'])
                 strategy.options[:scope] = scope
                 # Re-auth for an already-signed-in user (e.g. refreshing the
                 # access token at sync time). Pin the account via login_hint and
                 # drop the forced account chooser so the redirect is seamless;
                 # Google still falls back to a login screen if interaction is
                 # genuinely required.
                 strategy.options[:prompt]     = nil
                 strategy.options[:login_hint] = session['email'] if session['email']
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
