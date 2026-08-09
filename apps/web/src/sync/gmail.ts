// Port of apps/api/lib/gmail_client.rb (request/response shaping only).
// The actual fetch is performed by the caller with the browser access token;
// these helpers keep the batch multipart handling pure and testable.

export const GMAIL_BASE = "https://gmail.googleapis.com/gmail/v1";
export const BATCH_URL = "https://www.googleapis.com/batch/gmail/v1";
export const BATCH_BOUNDARY = "batch_boundary_gmail_v1";

// Limits the response to only what the decoder needs (matches Ruby THREAD_FIELDS).
export const THREAD_FIELDS =
  "messages/id,messages/internalDate,messages/payload/parts/mimeType,messages/payload/parts/body/data";

export interface GmailPart {
  mimeType?: string;
  body?: { data?: string };
}
export interface GmailMessage {
  id?: string;
  internalDate?: string;
  payload?: { parts?: GmailPart[] };
}
export interface GmailThread {
  messages?: GmailMessage[];
}

// Build the multipart/mixed body for a batched users.threads.get request.
export function buildBatchBody(ids: string[]): string {
  const parts = ids.map(
    (id, i) =>
      `--${BATCH_BOUNDARY}\r\n` +
      "Content-Type: application/http\r\n" +
      `Content-ID: <${i}>\r\n\r\n` +
      `GET /gmail/v1/users/me/threads/${encodeURIComponent(id)}?fields=${THREAD_FIELDS}\r\n\r\n`,
  );
  return parts.join("") + `--${BATCH_BOUNDARY}--\r\n`;
}

// Parse a multipart/mixed batch response into threads, positioned by the
// `Content-ID: <response-N>` index (mirrors the request order). A non-2xx inner
// part throws with the Gmail error message. Slots for parts Google omits stay
// undefined so callers can skip them (Ruby returns nil in the same spot).
export function parseBatchResponse(text: string, contentType: string): (GmailThread | undefined)[] {
  const boundaryMatch = contentType.match(/boundary=([^\s;]+)/);
  if (!boundaryMatch) throw new Error("batch response missing boundary");

  const rawParts = text.split(`--${boundaryMatch[1]}`).slice(1, -1);
  const result: (GmailThread | undefined)[] = [];

  rawParts.forEach((part, order) => {
    const outerSep = part.indexOf("\r\n\r\n");
    if (outerSep === -1) return;
    const outerHeaders = part.slice(0, outerSep);
    const httpResponse = part.slice(outerSep + 4);

    const bodySep = httpResponse.indexOf("\r\n\r\n");
    const head = bodySep === -1 ? httpResponse : httpResponse.slice(0, bodySep);
    const body = bodySep === -1 ? "" : httpResponse.slice(bodySep + 4);

    const status = Number(head.split(/\s+/)[1]);
    if (!(status >= 200 && status < 300)) {
      let message: string | undefined;
      try {
        message = (JSON.parse(body) as { error?: { message?: string } }).error?.message;
      } catch {
        // non-JSON error body; fall back to the status alone
      }
      throw new Error(`Gmail batch part error: ${[status, message].filter(Boolean).join(" ")}`);
    }

    const idxMatch = outerHeaders.match(/Content-ID:\s*<?response-(\d+)>?/i);
    const index = idxMatch ? Number(idxMatch[1]) : order;
    result[index] = JSON.parse(body.trim()) as GmailThread;
  });

  return result;
}
