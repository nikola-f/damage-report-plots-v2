# frozen_string_literal: true

require "rails_helper"

RSpec.describe GmailClient do
  let(:access_token) { "ya29.test_access_token" }
  let(:client) { described_class.new(access_token) }

  describe "#consume_quota (via public methods)" do
    let(:redis) { instance_double(Redis) }
    let(:token_hash) { Digest::SHA256.hexdigest(access_token) }
    let(:client_with_redis) { described_class.new(access_token, redis: redis) }

    before do
      stub_request(:get, "https://gmail.googleapis.com/gmail/v1/users/me/threads")
        .with(query: hash_including("fields" => "threads/id,nextPageToken"))
        .to_return(status: 200, body: { "threads" => [] }.to_json, headers: { "Content-Type" => "application/json" })
    end

    context "when redis is nil" do
      it "skips quota check and calls the API normally" do
        expect { client.list_threads }.not_to raise_error
      end
    end

    context "when within quota limits" do
      before do
        allow(redis).to receive(:incrby).with("gmail_quota:project", 10).and_return(10)
        allow(redis).to receive(:incrby).with("gmail_quota:user:#{token_hash}", 10).and_return(10)
        allow(redis).to receive(:expire)
      end

      it "calls incrby for both per-project and per-user keys" do
        client_with_redis.list_threads
        expect(redis).to have_received(:incrby).with("gmail_quota:project", 10)
        expect(redis).to have_received(:incrby).with("gmail_quota:user:#{token_hash}", 10)
      end
    end

    context "on the first call (new key)" do
      before do
        allow(redis).to receive(:incrby).and_return(10)  # new_count == units → first call
        allow(redis).to receive(:expire)
      end

      it "sets TTL of QUOTA_WINDOW seconds on the key" do
        client_with_redis.list_threads
        expect(redis).to have_received(:expire).with("gmail_quota:project", GmailClient::QUOTA_WINDOW)
        expect(redis).to have_received(:expire).with("gmail_quota:user:#{token_hash}", GmailClient::QUOTA_WINDOW)
      end
    end

    context "on a subsequent call (key already exists)" do
      before do
        allow(redis).to receive(:incrby).and_return(20)  # new_count != units → not first call
        allow(redis).to receive(:expire)
      end

      it "does not reset the TTL" do
        client_with_redis.list_threads
        expect(redis).not_to have_received(:expire)
      end
    end

    context "when per-project quota is exceeded" do
      before do
        allow(redis).to receive(:incrby)
          .with("gmail_quota:project", 10)
          .and_return(GmailClient::PER_PROJECT_LIMIT + 1)
        allow(redis).to receive(:expire)
      end

      it "raises QuotaExceededError" do
        expect { client_with_redis.list_threads }
          .to raise_error(GmailClient::QuotaExceededError, /gmail_quota:project/)
      end
    end

    context "when per-user quota is exceeded" do
      before do
        allow(redis).to receive(:incrby)
          .with("gmail_quota:project", 10).and_return(100)
        allow(redis).to receive(:incrby)
          .with("gmail_quota:user:#{token_hash}", 10)
          .and_return(GmailClient::PER_USER_LIMIT + 1)
        allow(redis).to receive(:expire)
      end

      it "raises QuotaExceededError" do
        expect { client_with_redis.list_threads }
          .to raise_error(GmailClient::QuotaExceededError, /gmail_quota:user:#{token_hash}/)
      end
    end

    context "with batch_get_threads" do
      let(:boundary) { "resp_boundary" }
      let(:thread) { { "id" => "t1", "messages" => [] } }
      let(:batch_body) do
        "--#{boundary}\r\n" \
          "Content-Type: application/http\r\nContent-ID: response-0\r\n\r\n" \
          "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" \
          "#{thread.to_json}\r\n" \
          "--#{boundary}--\r\n"
      end

      before do
        stub_request(:post, "https://www.googleapis.com/batch/gmail/v1")
          .to_return(status: 200, body: batch_body,
                     headers: { "Content-Type" => "multipart/mixed; boundary=#{boundary}" })
        allow(redis).to receive(:incrby).and_return(5)
        allow(redis).to receive(:expire)
      end

      it "consumes quota units proportional to the number of ids" do
        client_with_redis.batch_get_threads(%w[t1 t2 t3])
        expect(redis).to have_received(:incrby)
          .with("gmail_quota:project", GmailClient::QUOTA_UNITS[:batch_get_threads_per_id] * 3)
      end
    end
  end

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
