import { describe, it, expect } from "vitest";
import { buildBatchBody, parseBatchResponse, BATCH_BOUNDARY, THREAD_FIELDS } from "./gmail";

describe("buildBatchBody", () => {
  it("emits one sub-request per id with the fields mask and closing delimiter", () => {
    const body = buildBatchBody(["abc", "d/e"]);
    expect(body).toContain(`--${BATCH_BOUNDARY}\r\nContent-Type: application/http`);
    expect(body).toContain(`GET /gmail/v1/users/me/threads/abc?fields=${THREAD_FIELDS}`);
    expect(body).toContain("threads/d%2Fe"); // id path-segment is encoded
    expect(body.endsWith(`--${BATCH_BOUNDARY}--\r\n`)).toBe(true);
  });
});

function part(index: number, status: string, json: string): string {
  return (
    `--batchX\r\n` +
    `Content-Type: application/http\r\n` +
    `Content-ID: <response-${index}>\r\n\r\n` +
    `HTTP/1.1 ${status}\r\n` +
    `Content-Type: application/json\r\n\r\n` +
    `${json}\r\n`
  );
}

describe("parseBatchResponse", () => {
  const ctype = "multipart/mixed; boundary=batchX";

  it("parses threads and positions them by response index", () => {
    const text =
      part(0, "200 OK", '{"messages":[{"id":"m0","internalDate":"111"}]}') +
      part(1, "200 OK", '{"messages":[{"id":"m1","internalDate":"222"}]}') +
      `--batchX--\r\n`;
    const threads = parseBatchResponse(text, ctype);
    expect(threads[0]?.messages?.[0]?.id).toBe("m0");
    expect(threads[1]?.messages?.[0]?.internalDate).toBe("222");
  });

  it("throws with the Gmail error message on a non-2xx part", () => {
    const text =
      part(0, "404 Not Found", '{"error":{"message":"Requested entity was not found."}}') +
      `--batchX--\r\n`;
    expect(() => parseBatchResponse(text, ctype)).toThrow(/404 Requested entity was not found/);
  });

  it("throws when the boundary is missing", () => {
    expect(() => parseBatchResponse("whatever", "text/plain")).toThrow(/missing boundary/);
  });
});
