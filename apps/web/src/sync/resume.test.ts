import { describe, it, expect, vi } from "vitest";
import { readResumeSince } from "./resume";
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
