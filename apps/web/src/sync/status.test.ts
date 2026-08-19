import { describe, it, expect, vi } from "vitest";
import { readStats } from "./status";
import type { FetchLike } from "./http";

function valuesResponse(values: unknown[][] | undefined): Response {
  return new Response(JSON.stringify({ values }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

describe("readStats", () => {
  it("maps the stats column and converts report times to epoch seconds", async () => {
    // [version, portals, owned, pct, MIN(F)=oldest, MAX(E)=latest]
    const rows = [["0.0.0"], [42], [7], [99], [16_990_560], [16_999_200]];
    const fetchFn = vi.fn(async () => valuesResponse(rows));
    const s = await readStats("tok", "S1", fetchFn as unknown as FetchLike);
    expect(s).toEqual({
      portals: 42,
      ownedPortals: 7,
      oldestReport: 1_699_056_000, // 16_990_560 * 100
      latestReport: 1_699_920_000, // 16_999_200 * 100
    });
  });

  it("returns zeros and undefined times for a brand-new empty sheet", async () => {
    const fetchFn = vi.fn(async () => valuesResponse(undefined));
    const s = await readStats("tok", "S1", fetchFn as unknown as FetchLike);
    expect(s).toEqual({ portals: 0, ownedPortals: 0, latestReport: undefined, oldestReport: undefined });
  });

  it("treats non-numeric / zero report times as no data", async () => {
    const rows = [["0.0.0"], [3], [0], [1], [""], [0]];
    const fetchFn = vi.fn(async () => valuesResponse(rows));
    const s = await readStats("tok", "S1", fetchFn as unknown as FetchLike);
    expect(s.portals).toBe(3);
    expect(s.latestReport).toBeUndefined();
    expect(s.oldestReport).toBeUndefined();
  });
});
