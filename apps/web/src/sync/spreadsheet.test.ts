import { describe, it, expect, vi } from "vitest";
import { findOrCreateSpreadsheetId } from "./spreadsheet";
import type { FetchLike } from "./http";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// Route by method + URL so we can assert which calls happened. The two Drive
// listings differ only by their `q`: one filters on the appProperties marker,
// the other is the untagged-recovery search.
function router(tagged: { id: string }[], untagged: { id: string }[] = []): ReturnType<typeof vi.fn> {
  return vi.fn(async (input: string, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    if (url.includes("/drive/v3/files/")) return jsonResponse({}); // tag (PATCH)
    if (url.includes("/drive/v3/files"))
      return jsonResponse({ files: url.includes("appProperties") ? tagged : untagged });
    if (url.endsWith("/v4/spreadsheets") && method === "POST") return jsonResponse({ spreadsheetId: "NEW" });
    if (url.includes(":batchUpdate")) return jsonResponse({}); // protect
    throw new Error(`unexpected ${method} ${url}`);
  });
}

function labelCalls(fetchFn: ReturnType<typeof vi.fn>): string[] {
  return fetchFn.mock.calls.map((c) => {
    const url = String(c[0]);
    const method = (c[1] as RequestInit | undefined)?.method ?? "GET";
    const what = url.includes(":batchUpdate")
      ? "batchUpdate"
      : url.includes("/drive/v3/files/")
        ? "tag"
        : url.includes("/drive/v3/files")
          ? url.includes("appProperties")
            ? "list(marker)"
            : "list(untagged)"
          : "create";
    return `${method} ${what}`;
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
    expect(labelCalls(fetchFn)).toEqual([
      "GET list(marker)",
      "GET list(untagged)",
      "POST create",
      "POST batchUpdate",
      "PATCH tag",
    ]);
  });

  // A create that succeeded but whose tagging did not leaves a spreadsheet the
  // marker search can never find. Creating a second one would strand the
  // first's data for good, because drive.file offers no other route back to it.
  it("adopts an untagged spreadsheet instead of creating a second one", async () => {
    const fetchFn = router([], [{ id: "ORPHAN" }]);
    const result = await findOrCreateSpreadsheetId(
      "tok",
      fetchFn as unknown as FetchLike,
      { properties: { title: "t" } },
      { requests: [{ addProtectedRange: {} }] },
    );

    expect(result).toEqual({ spreadsheetId: "ORPHAN", created: false });
    expect(labelCalls(fetchFn)).toEqual(["GET list(marker)", "GET list(untagged)", "PATCH tag"]);
  });
});
