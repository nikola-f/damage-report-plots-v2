import { describe, it, expect, vi } from "vitest";
import { readResumeSince, readSyncPointer, writeSyncPointer, SYNC_POINTER_RANGE } from "./resume";
import type { FetchLike } from "./http";

function valuesResponse(values: unknown[][] | undefined): Response {
  return new Response(JSON.stringify({ values }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

describe("readResumeSince", () => {
  it("converts the truncated 100-second value back to a day-aligned epoch second", async () => {
    // 19675 days * 864 = 16_999_200 (a lastReportTime value) → *100 = 1_699_920_000
    const fetchFn = vi.fn(async (_u: string, _i?: RequestInit) => valuesResponse([[16_999_200]]));
    expect(await readResumeSince("tok", "S1", fetchFn as unknown as FetchLike)).toBe(1_699_920_000);
  });

  it("returns undefined for an empty sheet (no reports yet)", async () => {
    const fetchFn = vi.fn(async (_u: string, _i?: RequestInit) => valuesResponse(undefined));
    expect(await readResumeSince("tok", "S1", fetchFn as unknown as FetchLike)).toBeUndefined();
  });

  it("returns undefined when the value is not a positive number", async () => {
    const fetchFn = vi.fn(async (_u: string, _i?: RequestInit) => valuesResponse([[0]]));
    expect(await readResumeSince("tok", "S1", fetchFn as unknown as FetchLike)).toBeUndefined();
  });
});

describe("sync pointer", () => {
  it("reads the raw internalDate high-water mark as-is (already ms)", async () => {
    const fetchFn = vi.fn(async (_u: string, _i?: RequestInit) =>
      valuesResponse([[1_700_000_000_000]]),
    );
    expect(await readSyncPointer("tok", "S1", fetchFn as unknown as FetchLike)).toBe(
      1_700_000_000_000,
    );
  });

  it("returns undefined for sheets created before the pointer cell was written", async () => {
    const fetchFn = vi.fn(async (_u: string, _i?: RequestInit) => valuesResponse(undefined));
    expect(await readSyncPointer("tok", "S1", fetchFn as unknown as FetchLike)).toBeUndefined();
  });

  it("writes the pointer to the stats cell with PUT", async () => {
    const calls: { url: string; init?: RequestInit }[] = [];
    const fetchFn = vi.fn(async (url: string, init?: RequestInit) => {
      calls.push({ url, init });
      return valuesResponse([]);
    });

    await writeSyncPointer("tok", "S1", 1_700_000_000_000, fetchFn as unknown as FetchLike);

    expect(SYNC_POINTER_RANGE).toBe("stats!A7");
    expect(calls[0].init?.method).toBe("PUT");
    expect(calls[0].url).toContain("stats%21A7");
    expect(JSON.parse(calls[0].init?.body as string)).toEqual({ values: [[1_700_000_000_000]] });
  });
});
