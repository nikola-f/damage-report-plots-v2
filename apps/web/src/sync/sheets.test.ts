import { describe, it, expect, vi } from "vitest";
import { createSpreadsheet, appendRows, getValues, protectRanges } from "./sheets";
import type { FetchLike } from "./http";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function mockFetch(body: unknown, status = 200) {
  return vi.fn(async (_url: string, _init?: RequestInit) => jsonResponse(body, status));
}

describe("createSpreadsheet", () => {
  it("POSTs the definition and returns the new id", async () => {
    const fetchFn = mockFetch({ spreadsheetId: "NEW" });
    const id = await createSpreadsheet("tok", { properties: { title: "t" } }, fetchFn as unknown as FetchLike);

    expect(id).toBe("NEW");
    const [url, init] = fetchFn.mock.calls[0];
    expect(String(url)).toMatch(/\/v4\/spreadsheets$/);
    expect(init?.method).toBe("POST");
  });

  it("throws when the response carries no id", async () => {
    const fetchFn = mockFetch({});
    await expect(createSpreadsheet("tok", {}, fetchFn as unknown as FetchLike)).rejects.toThrow(/no id/);
  });
});

describe("appendRows", () => {
  it("appends RAW values to the sheet's A1 range", async () => {
    const fetchFn = mockFetch({});
    await appendRows("tok", "S1", "reports", [[1, 2, 3]], fetchFn as unknown as FetchLike);

    const [url, init] = fetchFn.mock.calls[0];
    const u = String(url);
    expect(u).toContain("/spreadsheets/S1/values/reports%21A1:append");
    expect(u).toContain("valueInputOption=RAW");
    expect(JSON.parse(init?.body as string)).toEqual({ values: [[1, 2, 3]] });
  });
});

describe("getValues", () => {
  it("returns the values grid", async () => {
    const fetchFn = mockFetch({ values: [[1, 2]] });
    expect(await getValues("tok", "S1", "plots!A:F", fetchFn as unknown as FetchLike)).toEqual([[1, 2]]);
  });

  it("returns [] when the range is empty", async () => {
    const fetchFn = mockFetch({});
    expect(await getValues("tok", "S1", "plots!A:F", fetchFn as unknown as FetchLike)).toEqual([]);
  });
});

describe("protectRanges", () => {
  it("no-ops when there are no requests", async () => {
    const fetchFn = mockFetch({});
    await protectRanges("tok", "S1", { requests: [] }, fetchFn as unknown as FetchLike);
    expect(fetchFn).not.toHaveBeenCalled();
  });

  it("POSTs a batchUpdate when requests exist", async () => {
    const fetchFn = mockFetch({});
    await protectRanges("tok", "S1", { requests: [{ addProtectedRange: {} }] }, fetchFn as unknown as FetchLike);

    const [url, init] = fetchFn.mock.calls[0];
    expect(String(url)).toContain("/spreadsheets/S1:batchUpdate");
    expect(init?.method).toBe("POST");
  });
});
