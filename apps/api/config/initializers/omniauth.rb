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

# Allow GET for the OAuth request phase.
#
# The SPA starts the flow with a top-level navigation (window.location ->
# /auth/google_oauth2). The request phase must end in a full-page redirect to
# accounts.google.com, which fetch/XHR cannot perform, so a GET navigation is
# unavoidable here.
#
# Allowing GET bypasses omniauth-rails_csrf_protection's request-phase token
# check, but the dangerous "login CSRF" variant (injecting an attacker's auth
# code into the victim's session) is still blocked downstream:
#   - The callback verifies the OAuth `state` parameter, which omniauth-oauth2
#     does by default (unless provider_ignores_state is enabled). An attacker's
#     code, obtained under a different session/state, fails this check.
#     Regression-pinned in spec/initializers/omniauth_security_spec.rb.
#   - The scope-upgrade request phase reads `requested_scope` from the session,
#     which only the authenticated, same-origin POST /auth/grant/* can set; a
#     forced GET without it degrades to a harmless plain re-login.
OmniAuth.config.allowed_request_methods = %i[get post]

# Handle failures
OmniAuth.config.on_failure = proc { |env|
  SessionsController.action(:failure).call(env)
}
