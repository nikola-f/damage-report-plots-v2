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
        .with(query: hash_including("fields" => "threads/id,nextPageToken"))
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
        .with(
          query: hash_including("fields" => "threads/id,nextPageToken"),
          headers: { "Authorization" => "Bearer ya29.test_access_token" }
        )
    end

    it "sends fields parameter to limit response fields" do
      client.list_threads
      expect(WebMock).to have_requested(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
        .with(query: hash_including("fields" => "threads/id,nextPageToken"))
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
          .with(query: hash_including("fields" => "threads/id,nextPageToken"))
          .to_return(
            status: 401,
            body: { "error" => { "code" => 401, "message" => "Invalid Credentials" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ApiError" do
        expect { client.list_threads }.to raise_error(GmailClient::ApiError, /401/)
      end

      # The raw body can carry user data (mail snippets, etc.) and ends up in
      # logs via the exception message — only status + error.message may leak.
      it "carries the status and Google's error message, not the raw body" do
        expect { client.list_threads }.to raise_error(GmailClient::ApiError) do |e|
          expect(e.message).to eq("Gmail API error: 401 Invalid Credentials")
        end
      end
    end

    context "when API returns 403" do
      before do
        stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
          .with(query: hash_including("fields" => "threads/id,nextPageToken"))
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

  describe "#batch_get_threads" do
    let(:boundary) { "response_boundary_123" }
    let(:content_type) { "multipart/mixed; boundary=#{boundary}" }

    def build_batch_response_body(parts, boundary:)
      body = parts.map.with_index do |part, i|
        "--#{boundary}\r\n" \
          "Content-Type: application/http\r\n" \
          "Content-ID: response-#{i}\r\n" \
          "\r\n" \
          "HTTP/1.1 #{part[:status]} #{part[:status] == 200 ? "OK" : "Error"}\r\n" \
          "Content-Type: application/json\r\n" \
          "\r\n" \
          "#{part[:body].to_json}\r\n"
      end
      body.join + "--#{boundary}--\r\n"
    end

    context "when ids is empty" do
      it "returns [] without making any HTTP request" do
        result = client.batch_get_threads([])
        expect(result).to eq([])
        expect(WebMock).not_to have_requested(:post, "https://www.googleapis.com/batch/gmail/v1")
      end
    end

    context "with a single ID" do
      let(:thread) { { "id" => "thread_1", "messages" => [] } }

      before do
        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(
            status: 200,
            body: build_batch_response_body([{ status: 200, body: thread }], boundary: boundary),
            headers: { "Content-Type" => content_type }
          )
      end

      it "returns an array with the single thread" do
        result = client.batch_get_threads(["thread_1"])
        expect(result.length).to eq(1)
        expect(result[0]["id"]).to eq("thread_1")
      end
    end

    context "with multiple IDs" do
      let(:thread_1) { { "id" => "thread_1", "messages" => [] } }
      let(:thread_2) { { "id" => "thread_2", "messages" => [] } }
      let(:thread_3) { { "id" => "thread_3", "messages" => [] } }

      before do
        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(
            status: 200,
            body: build_batch_response_body(
              [
                { status: 200, body: thread_1 },
                { status: 200, body: thread_2 },
                { status: 200, body: thread_3 }
              ],
              boundary: boundary
            ),
            headers: { "Content-Type" => content_type }
          )
      end

      it "returns threads in the same order as input ids" do
        result = client.batch_get_threads(%w[thread_1 thread_2 thread_3])
        expect(result.map { |t| t["id"] }).to eq(%w[thread_1 thread_2 thread_3])
      end
    end

    context "when Content-ID uses angle brackets (<response-N> format, as per RFC 2392)" do
      let(:thread_1) { { "id" => "thread_1", "messages" => [] } }
      let(:thread_2) { { "id" => "thread_2", "messages" => [] } }

      before do
        body =
          "--#{boundary}\r\n" \
          "Content-Type: application/http\r\n" \
          "Content-ID: <response-0>\r\n" \
          "\r\n" \
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "\r\n" \
          "#{thread_1.to_json}\r\n" \
          "--#{boundary}\r\n" \
          "Content-Type: application/http\r\n" \
          "Content-ID: <response-1>\r\n" \
          "\r\n" \
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "\r\n" \
          "#{thread_2.to_json}\r\n" \
          "--#{boundary}--\r\n"

        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(status: 200, body: body,
                     headers: { "Content-Type" => content_type })
      end

      it "returns all threads in the correct order" do
        result = client.batch_get_threads(%w[thread_1 thread_2])
        expect(result.map { |t| t["id"] }).to eq(%w[thread_1 thread_2])
      end
    end

    context "when response parts arrive in reverse order" do
      let(:thread_a) { { "id" => "thread_a", "messages" => [] } }
      let(:thread_b) { { "id" => "thread_b", "messages" => [] } }

      before do
        # Parts are in reverse order (index 1 first, then index 0)
        reversed_body =
          "--#{boundary}\r\n" \
          "Content-Type: application/http\r\n" \
          "Content-ID: response-1\r\n" \
          "\r\n" \
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "\r\n" \
          "#{thread_b.to_json}\r\n" \
          "--#{boundary}\r\n" \
          "Content-Type: application/http\r\n" \
          "Content-ID: response-0\r\n" \
          "\r\n" \
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "\r\n" \
          "#{thread_a.to_json}\r\n" \
          "--#{boundary}--\r\n"

        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(
            status: 200,
            body: reversed_body,
            headers: { "Content-Type" => content_type }
          )
      end

      it "returns threads in the same order as input ids regardless of response order" do
        result = client.batch_get_threads(%w[thread_a thread_b])
        expect(result[0]["id"]).to eq("thread_a")
        expect(result[1]["id"]).to eq("thread_b")
      end
    end

    context "when a batch part returns 404" do
      let(:thread_1) { { "id" => "thread_1", "messages" => [] } }

      before do
        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(
            status: 200,
            body: build_batch_response_body(
              [
                { status: 200, body: thread_1 },
                { status: 404, body: { "error" => { "code" => 404, "message" => "Not Found" } } }
              ],
              boundary: boundary
            ),
            headers: { "Content-Type" => content_type }
          )
      end

      it "raises ApiError" do
        expect { client.batch_get_threads(%w[thread_1 thread_missing]) }
          .to raise_error(GmailClient::ApiError, /404/)
      end

      it "includes the error message from the response body" do
        expect { client.batch_get_threads(%w[thread_1 thread_missing]) }
          .to raise_error(GmailClient::ApiError, /Not Found/)
      end
    end

    context "when the outer request returns 401" do
      before do
        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(
            status: 401,
            body: { "error" => { "code" => 401, "message" => "Invalid Credentials" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ApiError" do
        expect { client.batch_get_threads(["thread_1"]) }
          .to raise_error(GmailClient::ApiError, /401/)
      end
    end

    context "Authorization header" do
      let(:thread) { { "id" => "thread_1", "messages" => [] } }

      before do
        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(
            status: 200,
            body: build_batch_response_body([{ status: 200, body: thread }], boundary: boundary),
            headers: { "Content-Type" => content_type }
          )
      end

      it "sends Authorization header with Bearer token on the outer request" do
        client.batch_get_threads(["thread_1"])
        expect(WebMock).to have_requested(:post, "https://www.googleapis.com/batch/gmail/v1")
          .with(headers: { "Authorization" => "Bearer ya29.test_access_token" })
      end
    end

    context "fields parameter" do
      let(:thread) { { "id" => "thread_1", "messages" => [] } }

      before do
        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(
            status: 200,
            body: build_batch_response_body([{ status: 200, body: thread }], boundary: boundary),
            headers: { "Content-Type" => content_type }
          )
      end

      it "includes fields parameter in each batch part URL" do
        client.batch_get_threads(["thread_1"])
        expect(WebMock).to have_requested(:post, "https://www.googleapis.com/batch/gmail/v1")
          .with(body: /fields=#{Regexp.escape(GmailClient::THREAD_FIELDS)}/)
      end
    end
  end
end
