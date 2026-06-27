# frozen_string_literal: true

require "rails_helper"
require "omniauth-google-oauth2"

# Security regression for the OAuth request phase.
#
# config/initializers/omniauth.rb allows GET for the request phase (the SPA must
# start the flow with a top-level navigation). That bypasses
# omniauth-rails_csrf_protection's request-phase token check, so the callback's
# defense against login CSRF rests on the OAuth `state` parameter, which
# omniauth-oauth2 verifies only while `provider_ignores_state` is off.
#
# These examples pin that assumption: if a gem upgrade flips the default, or
# someone sets `provider_ignores_state: true`, the build fails here.
RSpec.describe "OmniAuth Google OAuth2 security configuration" do
  it "verifies the OAuth state parameter by default (provider_ignores_state off)" do
    app      = ->(_env) { [200, {}, ["ok"]] }
    strategy = OmniAuth::Strategies::GoogleOauth2.new(app, "client_id", "client_secret")

    expect(strategy.options.provider_ignores_state).to be_falsey
  end

  it "does not enable provider_ignores_state in the initializer" do
    initializer = Rails.root.join("config/initializers/omniauth.rb").read

    # Matches an enabling assignment (`provider_ignores_state: true`,
    # `provider_ignores_state => true`) while ignoring mentions in comments.
    expect(initializer).not_to match(/provider_ignores_state\s*(?::|=>)\s*true/)
  end
end
