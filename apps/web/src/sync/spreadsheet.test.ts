import { describe, it, expect, vi } from "vitest";
import { findOrCreateSpreadsheetId } from "./spreadsheet";
import type { FetchLike } from "./http";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// Route by method + URL so we can assert which calls happened.
function router(files: { id: string }[]): ReturnType<typeof vi.fn> {
  return vi.fn(async (input: string, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    if (url.includes("/drive/v3/files/")) return jsonResponse({}); // tag (PATCH)
    if (url.includes("/drive/v3/files")) return jsonResponse({ files }); // list
    if (url.endsWith("/v4/spreadsheets") && method === "POST") return jsonResponse({ spreadsheetId: "NEW" });
    if (url.includes(":batchUpdate")) return jsonResponse({}); // protect
    throw new Error(`unexpected ${method} ${url}`);
  });
}

describe("findOrCreateSpreadsheetId", () => {
  it("reuses an existing spreadsheet without creating one", async () => {
    const fetchFn = router([{ id: "EXISTING" }]);
    const result = await findOrCreateSpreadsheetId("tok", fetchFn as unknown as FetchLike, {});

    expect(result).toEqual({ spreadsheetId: "EXISTING", created: false });
    // only the Drive list call was made
    expect(fetchFn).toHaveBeenCalledOnce();
  });

  it("creates, protects, and tags a new spreadsheet when none exists", async () => {
    const fetchFn = router([]);
    const result = await findOrCreateSpreadsheetId(
      "tok",
      fetchFn as unknown as FetchLike,
      { properties: { title: "t" } },
      { requests: [{ addProtectedRange: {} }] },
    );

    expect(result).toEqual({ spreadsheetId: "NEW", created: true });
    const calls = fetchFn.mock.calls.map((c) => {
      const init = c[1] as RequestInit | undefined;
      return `${init?.method ?? "GET"} ${String(c[0]).includes(":batchUpdate") ? "batchUpdate" : String(c[0]).includes("/drive/v3/files/") ? "tag" : String(c[0]).includes("/drive/v3/files") ? "list" : "create"}`;
    });
    expect(calls).toEqual(["GET list", "POST create", "POST batchUpdate", "PATCH tag"]);
  });
});
