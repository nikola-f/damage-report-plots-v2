# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleAuthorizationCodeFlow do
  let(:redirect_uri) { "https://api.example.com/auth/callback" }
  let(:mock_client) { instance_double(OAuth2::Client) }
  let(:mock_auth_code) { instance_double(OAuth2::Strategy::AuthCode) }

  def stub_credentials
    allow(Rails.application.credentials).to receive(:dig)
      .with(:google, :client_id).and_return("test_client_id")
    allow(Rails.application.credentials).to receive(:dig)
      .with(:google, :client_secret).and_return("test_client_secret")
  end

  def stub_oauth2_client
    allow(OAuth2::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:auth_code).and_return(mock_auth_code)
  end

  describe ".authorization_url" do
    let(:scope) { "https://www.googleapis.com/auth/gmail.readonly" }
    let(:expected_url) { "https://accounts.google.com/o/oauth2/auth?client_id=test_client_id&..." }

    before do
      stub_credentials
      stub_oauth2_client
      allow(mock_auth_code).to receive(:authorize_url).and_return(expected_url)
    end

    it "returns the authorization URL" do
      expect(described_class.authorization_url(redirect_uri: redirect_uri, scope: scope)).to eq(expected_url)
    end

    it "builds the OAuth2 client with correct credentials and URLs" do
      described_class.authorization_url(redirect_uri: redirect_uri, scope: scope)
      expect(OAuth2::Client).to have_received(:new).with(
        "test_client_id",
        "test_client_secret",
        authorize_url: GoogleAuthorizationCodeFlow::AUTHORIZATION_URL,
        token_url: GoogleAuthorizationCodeFlow::TOKEN_URL
      )
    end

    it "passes redirect_uri, scope, access_type, and include_granted_scopes" do
      described_class.authorization_url(redirect_uri: redirect_uri, scope: scope)
      expect(mock_auth_code).to have_received(:authorize_url).with(
        redirect_uri: redirect_uri,
        scope: scope,
        access_type: "online",
        include_granted_scopes: "true"
      )
    end

    context "with state" do
      it "includes state in the URL params" do
        described_class.authorization_url(redirect_uri: redirect_uri, scope: scope, state: "csrf_token")
        expect(mock_auth_code).to have_received(:authorize_url).with(
          redirect_uri: redirect_uri,
          scope: scope,
          access_type: "online",
          include_granted_scopes: "true",
          state: "csrf_token"
        )
      end
    end

    context "without state" do
      it "omits state from the URL params" do
        described_class.authorization_url(redirect_uri: redirect_uri, scope: scope)
        expect(mock_auth_code).to have_received(:authorize_url).with(
          hash_excluding(state: anything)
        )
      end
    end
  end

  describe ".fetch (integration)" do
    before do
      stub_credentials
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(
          status: 200,
          body: { access_token: "ya29.from_webmock", token_type: "Bearer", expires_in: 3600 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns the access token from Google's response" do
      result = described_class.fetch(code: "4/test_code", redirect_uri: "https://example.com/callback")
      expect(result).to eq("ya29.from_webmock")
    end

    it "sends the code and redirect_uri to Google's token endpoint" do
      described_class.fetch(code: "4/test_code", redirect_uri: "https://example.com/callback")
      expect(WebMock).to have_requested(:post, "https://oauth2.googleapis.com/token")
        .with(body: hash_including("code" => "4/test_code", "redirect_uri" => "https://example.com/callback"))
    end

    context "when Google returns an error" do
      before do
        stub_request(:post, "https://oauth2.googleapis.com/token")
          .to_return(
            status: 400,
            body: { error: "invalid_grant", error_description: "Code was already redeemed." }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises FetchError" do
        expect do
          described_class.fetch(code: "expired_code", redirect_uri: "https://example.com/callback")
        end.to raise_error(GoogleAuthorizationCodeFlow::FetchError)
      end
    end
  end

  describe ".fetch" do
    let(:code) { "4/test_code" }
    let(:mock_token) { instance_double(OAuth2::AccessToken, token: "ya29.new_token") }

    before do
      stub_credentials
      stub_oauth2_client
      allow(mock_auth_code).to receive(:get_token).and_return(mock_token)
    end

    context "with a valid code" do
      it "returns the access token string" do
        expect(described_class.fetch(code: code, redirect_uri: redirect_uri)).to eq("ya29.new_token")
      end

      it "builds the OAuth2 client with correct credentials and URLs" do
        described_class.fetch(code: code, redirect_uri: redirect_uri)
        expect(OAuth2::Client).to have_received(:new).with(
          "test_client_id",
          "test_client_secret",
          authorize_url: GoogleAuthorizationCodeFlow::AUTHORIZATION_URL,
          token_url: GoogleAuthorizationCodeFlow::TOKEN_URL
        )
      end

      it "exchanges the code with the redirect_uri" do
        described_class.fetch(code: code, redirect_uri: redirect_uri)
        expect(mock_auth_code).to have_received(:get_token).with(code, redirect_uri: redirect_uri)
      end
    end

    context "when Google returns an error" do
      before do
        error_response = instance_double(OAuth2::Response, parsed: { "error_description" => "invalid_grant" })
        allow(mock_auth_code).to receive(:get_token)
          .and_raise(OAuth2::Error.new(error_response))
      end

      it "raises FetchError" do
        expect { described_class.fetch(code: code, redirect_uri: redirect_uri) }
          .to raise_error(GoogleAuthorizationCodeFlow::FetchError)
      end
    end
  end
end
