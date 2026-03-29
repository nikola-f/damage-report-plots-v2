# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailClient do
  let(:access_token) { "ya29.test_access_token" }
  let(:client) { described_class.new(access_token) }

  describe "#list_threads" do
    let(:threads_response) do
      {
        "threads" => [
          { "id" => "thread_1", "snippet" => "Portal under attack..." },
          { "id" => "thread_2", "snippet" => "Damage report..." }
        ],
        "nextPageToken" => "next_page_token_abc",
        "resultSizeEstimate" => 42
      }
    end

    before do
      stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
        .to_return(
          status: 200,
          body: threads_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns parsed thread list" do
      result = client.list_threads
      expect(result["threads"].length).to eq(2)
      expect(result["threads"][0]["id"]).to eq("thread_1")
      expect(result["nextPageToken"]).to eq("next_page_token_abc")
      expect(result["resultSizeEstimate"]).to eq(42)
    end

    it "sends Authorization header with Bearer token" do
      client.list_threads
      expect(WebMock).to have_requested(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
        .with(headers: { "Authorization" => "Bearer ya29.test_access_token" })
    end

    context "with q parameter" do
      before do
        stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
          .with(query: hash_including("q" => "subject:damage report"))
          .to_return(status: 200, body: threads_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "passes q as query parameter" do
        client.list_threads(q: "subject:damage report")
        expect(WebMock).to have_requested(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
          .with(query: hash_including("q" => "subject:damage report"))
      end
    end

    context "with page_token parameter" do
      before do
        stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
          .with(query: hash_including("pageToken" => "next_page_token_abc"))
          .to_return(status: 200, body: threads_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "passes pageToken as query parameter" do
        client.list_threads(page_token: "next_page_token_abc")
        expect(WebMock).to have_requested(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
          .with(query: hash_including("pageToken" => "next_page_token_abc"))
      end
    end

    context "when API returns 401" do
      before do
        stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
          .to_return(
            status: 401,
            body: { "error" => { "code" => 401, "message" => "Invalid Credentials" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ApiError" do
        expect { client.list_threads }.to raise_error(GmailClient::ApiError, /401/)
      end
    end

    context "when API returns 403" do
      before do
        stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
          .to_return(
            status: 403,
            body: { "error" => { "code" => 403, "message" => "Insufficient Permission" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ApiError" do
        expect { client.list_threads }.to raise_error(GmailClient::ApiError, /403/)
      end
    end
  end

  describe "#get_thread" do
    let(:thread_id) { "thread_abc123" }
    let(:thread_response) do
      {
        "id" => thread_id,
        "snippet" => "Portal under attack...",
        "messages" => [
          { "id" => "msg_1", "threadId" => thread_id, "payload" => { "body" => { "data" => "encoded_body" } } }
        ]
      }
    end

    before do
      stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads/#{thread_id}")
        .to_return(
          status: 200,
          body: thread_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns the parsed thread" do
      result = client.get_thread(thread_id)
      expect(result["id"]).to eq(thread_id)
      expect(result["messages"].length).to eq(1)
      expect(result["messages"][0]["id"]).to eq("msg_1")
    end

    it "sends Authorization header with Bearer token" do
      client.get_thread(thread_id)
      expect(WebMock).to have_requested(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads/#{thread_id}")
        .with(headers: { "Authorization" => "Bearer ya29.test_access_token" })
    end

    context "when API returns 404" do
      before do
        stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads/#{thread_id}")
          .to_return(
            status: 404,
            body: { "error" => { "code" => 404, "message" => "Not Found" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ApiError" do
        expect { client.get_thread(thread_id) }.to raise_error(GmailClient::ApiError, /404/)
      end
    end
  end
end
