import { describe, it, expect, vi } from "vitest";
import { findSpreadsheetId, tagSpreadsheet, MARKER_KEY } from "./drive";
import type { FetchLike } from "./http";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function mockFetch(body: unknown, status = 200) {
  return vi.fn(async (_url: string, _init?: RequestInit) => jsonResponse(body, status));
}

describe("findSpreadsheetId", () => {
  it("queries by the appProperties marker, oldest-first, and returns the id", async () => {
    const fetchFn = mockFetch({ files: [{ id: "S1", createdTime: "2024" }] });
    const id = await findSpreadsheetId("tok", fetchFn as unknown as FetchLike);

    expect(id).toBe("S1");
    // URLSearchParams encodes spaces as "+"; normalize before matching.
    const decoded = decodeURIComponent(String(fetchFn.mock.calls[0][0])).replace(/\+/g, " ");
    expect(decoded).toContain(`appProperties has { key='${MARKER_KEY}' and value='1' }`);
    expect(decoded).toContain("orderBy=createdTime");
  });

  it("returns null when nothing matches", async () => {
    const fetchFn = mockFetch({ files: [] });
    expect(await findSpreadsheetId("tok", fetchFn as unknown as FetchLike)).toBeNull();
  });

  it("throws on a non-2xx response", async () => {
    const fetchFn = mockFetch({}, 403);
    await expect(findSpreadsheetId("tok", fetchFn as unknown as FetchLike)).rejects.toThrow(/403/);
  });
});

describe("tagSpreadsheet", () => {
  it("PATCHes the appProperties marker onto the file", async () => {
    const fetchFn = mockFetch({ id: "S1" });
    await tagSpreadsheet("tok", "S1", fetchFn as unknown as FetchLike);

    const [url, init] = fetchFn.mock.calls[0];
    expect(String(url)).toContain("/files/S1");
    expect(init?.method).toBe("PATCH");
    expect(JSON.parse(init?.body as string)).toEqual({ appProperties: { [MARKER_KEY]: "1" } });
  });
});
