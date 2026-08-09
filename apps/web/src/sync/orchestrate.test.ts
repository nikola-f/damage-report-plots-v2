import { describe, it, expect, vi } from "vitest";
import { runFullSync, readPlots } from "./orchestrate";
import { BATCH_URL } from "./gmail";
import type { FetchLike } from "./http";

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
}

function b64url(s: string): string {
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_");
}

function portalHtml(): string {
  return (
    `<table><tbody>` +
    `<tr><td><div>Alpha</div><div><a href="https://intel.ingress.com/intel?pll=35.1,139.2">m</a></div></td></tr>` +
    `<tr><td>Owner: Me</td></tr>` +
    `</tbody></table><span>Agent Name:</span><span>Me</span>`
  );
}

function batchResponse(): Response {
  const boundary = "batchX";
  const thread = {
    messages: [
      {
        id: "m1",
        internalDate: "1700000000000",
        payload: { parts: [{ mimeType: "text/html", body: { data: b64url(portalHtml()) } }] },
      },
    ],
  };
  const body =
    `--${boundary}\r\nContent-Type: application/http\r\nContent-ID: <response-0>\r\n\r\n` +
    `HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n${JSON.stringify(thread)}\r\n` +
    `--${boundary}--\r\n`;
  return new Response(body, {
    status: 200,
    headers: { "Content-Type": `multipart/mixed; boundary=${boundary}` },
  });
}

const SINCE_UNITS = 16_999_200; // lastReportTime value in 100-second units
const SINCE = SINCE_UNITS * 100; // epoch seconds
const UNTIL = SINCE + 5 * 86_400; // one 30-day window

describe("runFullSync", () => {
  it("resolves the sheet, resumes, scans, appends, and returns plots", async () => {
    const appendBodies: unknown[] = [];

    const fetchFn = vi.fn(async (input: string, init?: RequestInit) => {
      const url = String(input);
      if (url.startsWith(BATCH_URL)) return batchResponse();
      if (url.includes("/drive/v3/files")) return json({ files: [{ id: "SHEET" }] }); // existing sheet
      if (url.includes("gmail.googleapis.com")) return json({ threads: [{ id: "t1" }] });
      if (url.includes("/values/lastReportTime")) return json({ values: [[SINCE_UNITS]] });
      if (url.includes(":append")) {
        appendBodies.push(JSON.parse(init?.body as string));
        return json({});
      }
      throw new Error(`unexpected ${init?.method ?? "GET"} ${url}`);
    });

    const result = await runFullSync({
      accessToken: "tok",
      fetchFn: fetchFn as unknown as FetchLike,
      until: UNTIL,
      now: new Date(Date.UTC(2024, 0, 1)),
    });

    expect(result.spreadsheetId).toBe("SHEET");
    expect(result.appended).toBe(1);
    expect(result.truncated).toBe(false);
    expect(appendBodies).toHaveLength(1);
  });
});

describe("readPlots", () => {
  it("reads plots!A:F fresh and maps it to Plot objects", async () => {
    const fetchFn = vi.fn(async (url: string) => {
      expect(url).toContain("/values/plots");
      return json({ values: [[35.1, 139.2, 1, 3, 17_000_000, 16_990_000]] });
    });

    const plots = await readPlots("tok", "SHEET", fetchFn as unknown as FetchLike);
    expect(plots).toEqual([
      { lat: 35.1, lng: 139.2, owned: 1, count: 3, latest: 17_000_000, oldest: 16_990_000 },
    ]);
  });
});
