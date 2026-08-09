import { describe, it, expect } from "vitest";
import { buildQuery, DEFAULT_AFTER_DATE } from "./query";

describe("buildQuery", () => {
  it("builds the damage-report query with day-aligned bounds", () => {
    const after = Date.UTC(2024, 0, 1) / 1000; // 2024-01-01
    const before = Date.UTC(2024, 0, 31) / 1000; // 2024-01-31
    expect(buildQuery(after, before)).toBe(
      "subject:Ingress Damage Report: Entities attacked by " +
        "after:1704067200 before:1706659200 " +
        "{from:ingress-support@google.com from:ingress-support@nianticlabs.com from:ingress-support@nianticspatial.com} " +
        "larger:5K smaller:100K",
    );
  });

  it("aligns non-midnight epochs down to UTC midnight", () => {
    const after = Date.UTC(2024, 0, 1) / 1000 + 12_345;
    expect(buildQuery(after, after)).toContain("after:1704067200 before:1704067200");
  });

  it("exposes 2012-10-15 UTC as the default lower bound", () => {
    expect(DEFAULT_AFTER_DATE).toBe(1_350_259_200);
  });
});
