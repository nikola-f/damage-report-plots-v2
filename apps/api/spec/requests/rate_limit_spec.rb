# frozen_string_literal: true

require "rails_helper"

# Rack::Attack is disabled globally in test (config/initializers/rack_attack.rb)
# so the throttles don't interfere with other request specs; this file enables
# it per-example with a fresh in-memory counter store.
RSpec.describe "Rate limiting", type: :request do
  # Behind CloudFront → ALB, X-Forwarded-For arrives as
  # "<client-supplied...>, <viewer IP (appended by CloudFront)>, <edge IP (appended by ALB)>"
  # so the trustworthy client IP is the second-to-last entry.
  let(:viewer_ip) { "192.0.2.10" }
  let(:edge_ip)   { "130.176.0.1" }
  let(:xff)       { "#{viewer_ip}, #{edge_ip}" }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rack::Attack.enabled = false }

  describe "auth throttle (/auth/*)" do
    it "returns 429 with a JSON body and Retry-After once the limit is exceeded" do
      Settings.rate_limit_auth_limit.times do
        get "/auth/failure", headers: { "X-Forwarded-For" => xff }
        expect(response).to have_http_status(:unauthorized)
      end

      get "/auth/failure", headers: { "X-Forwarded-For" => xff }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
      expect(response.parsed_body).to eq("error" => "rate_limited")
    end

    it "keys on the CloudFront-appended viewer IP, not client-spoofable entries" do
      # Prepending junk to X-Forwarded-For must not give a fresh counter.
      Settings.rate_limit_auth_limit.times do |i|
        get "/auth/failure", headers: { "X-Forwarded-For" => "10.9.8.#{i}, #{xff}" }
      end

      get "/auth/failure", headers: { "X-Forwarded-For" => "10.9.8.99, #{xff}" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "counts different viewer IPs independently" do
      Settings.rate_limit_auth_limit.times do
        get "/auth/failure", headers: { "X-Forwarded-For" => xff }
      end

      get "/auth/failure", headers: { "X-Forwarded-For" => "192.0.2.99, #{edge_ip}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "global throttle" do
    it "returns 429 once the limit is exceeded" do
      Settings.rate_limit_global_limit.times do
        get "/api/v1/profile", headers: { "X-Forwarded-For" => xff }
        expect(response).to have_http_status(:unauthorized)
      end

      get "/api/v1/profile", headers: { "X-Forwarded-For" => xff }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "does not count the health check endpoint" do
      (Settings.rate_limit_global_limit + 1).times do
        get "/up", headers: { "X-Forwarded-For" => xff }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "without X-Forwarded-For (local/dev)" do
    it "falls back to the connection IP and still throttles" do
      Settings.rate_limit_auth_limit.times { get "/auth/failure" }

      get "/auth/failure"

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
