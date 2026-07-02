# frozen_string_literal: true

require "rails_helper"

# CSRF defense in depth: state-changing requests with an Origin header that
# does not match ALLOWED_ORIGINS are rejected before any other processing.
# SameSite=Lax on the session cookie remains the first line of defense.
RSpec.describe "Origin verification", type: :request do
  let(:allowed_origin) { Settings.allowed_origins.split(",").first }
  let(:evil_origin)    { "https://evil.example" }

  let(:access_token_store)   { instance_double(UserStore, fetch: "ya29.token", store: nil) }
  let(:spreadsheet_id_store) { instance_double(UserStore, fetch: "spreadsheet-id") }
  let(:counter_store)        { instance_double(UserStore, store: nil) }
  let(:last_synced_at_store) { instance_double(UserStore, store: nil) }

  before do
    allow(UserStore).to receive_messages(
      access_token:              access_token_store,
      spreadsheet_id:            spreadsheet_id_store,
      last_synced_at:            last_synced_at_store,
      threads_found:             counter_store,
      threads_processed:         counter_store,
      portals_found:             counter_store,
      portals_appended:          counter_store,
      threads_max_internal_date: instance_double(UserStore)
    )
    allow(UserStore.threads_max_internal_date).to receive(:fetch).and_raise(KeyError)
    allow(last_synced_at_store).to receive(:fetch).and_raise(KeyError)
    allow(GmailThreadListWorker).to receive(:perform_async)
  end

  context "with a mismatched Origin header" do
    it "rejects a state-changing request with 403 before authentication" do
      post "/api/v1/sync", headers: { "Origin" => evil_origin }

      expect(response).to have_http_status(:forbidden)
      expect(GmailThreadListWorker).not_to have_received(:perform_async)
    end

    it "rejects even with an active session" do
      login_as
      post "/api/v1/sync", headers: { "Origin" => evil_origin }

      expect(response).to have_http_status(:forbidden)
      expect(GmailThreadListWorker).not_to have_received(:perform_async)
    end

    it "rejects logout" do
      login_as
      delete "/auth/logout", headers: { "Origin" => evil_origin }

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects scope grant requests" do
      login_as
      post "/auth/grant/sync", headers: { "Origin" => evil_origin }

      expect(response).to have_http_status(:forbidden)
    end

    it "does not reject safe (GET) requests" do
      login_as
      get "/api/v1/profile", headers: { "Origin" => evil_origin }

      expect(response).to have_http_status(:ok)
    end
  end

  context "with an Origin of null" do
    # "null" is sent from sandboxed iframes and some redirect chains; it is
    # never a legitimate first-party origin.
    it "rejects a state-changing request with 403" do
      login_as
      post "/api/v1/sync", headers: { "Origin" => "null" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  context "with an allowed Origin header" do
    it "processes the request normally" do
      login_as
      post "/api/v1/sync", headers: { "Origin" => allowed_origin }

      expect(response).to have_http_status(:accepted)
    end
  end

  context "without an Origin header" do
    # Non-browser clients do not send Origin, but they do not carry ambient
    # cookies either, so CSRF does not apply to them.
    it "processes the request normally" do
      login_as
      post "/api/v1/sync"

      expect(response).to have_http_status(:accepted)
    end
  end

  describe ".normalize_origin" do
    # Browsers serialize the Origin header as scheme://host[:port] — no path,
    # no trailing slash, no default port. Configured values must be normalized
    # the same way or legitimate requests get rejected (e.g. ALLOWED_ORIGINS
    # with a trailing slash silently 403'd every SPA request in dev).
    it "strips a trailing slash" do
      expect(ApplicationController.normalize_origin("https://example.com/"))
        .to eq("https://example.com")
    end

    it "strips a default port" do
      expect(ApplicationController.normalize_origin("https://example.com:443"))
        .to eq("https://example.com")
    end

    it "keeps a non-default port" do
      expect(ApplicationController.normalize_origin("http://localhost:3000"))
        .to eq("http://localhost:3000")
    end

    it "strips surrounding whitespace" do
      expect(ApplicationController.normalize_origin(" https://example.com "))
        .to eq("https://example.com")
    end

    it "leaves an already-normalized origin unchanged" do
      expect(ApplicationController.normalize_origin("https://develop.example.com"))
        .to eq("https://develop.example.com")
    end
  end
end
