import { describe, it, expect } from "vitest";
import { deduplicate, portalId, type DamageReportRecord } from "./record";

function rec(p: Partial<DamageReportRecord> = {}): DamageReportRecord {
  return { name: "P", latitude: "1", longitude: "2", owned: false, internalDate: 100, ...p };
}

describe("deduplicate", () => {
  it("collapses same name/lat/lng/date and keeps owned:true", () => {
    const out = deduplicate([rec({ owned: false }), rec({ owned: true })]);
    expect(out).toHaveLength(1);
    expect(out[0].owned).toBe(true);
  });

  it("keeps owned:true even when it appears before the owned:false duplicate", () => {
    const out = deduplicate([rec({ owned: true }), rec({ owned: false })]);
    expect(out).toHaveLength(1);
    expect(out[0].owned).toBe(true);
  });

  it("keeps records that differ in any key field", () => {
    const out = deduplicate([rec({ internalDate: 100 }), rec({ internalDate: 200 })]);
    expect(out).toHaveLength(2);
  });

  it("preserves first-occurrence order", () => {
    const out = deduplicate([rec({ name: "A" }), rec({ name: "B" }), rec({ name: "A", owned: true })]);
    expect(out.map((r) => r.name)).toEqual(["A", "B"]);
  });
});

describe("portalId", () => {
  it("is deterministic for the same coordinates", async () => {
    expect(await portalId("35.681236", "139.767125")).toBe(await portalId("35.681236", "139.767125"));
  });

  it("differs for different coordinates", async () => {
    expect(await portalId("35.681236", "139.767125")).not.toBe(await portalId("0", "0"));
  });

  // Locks the whole derivation (SHA-256 → big-endian → 62-bit mask → 31-bit
  // split → sqids). Reference values captured from the chosen JS scheme.
  it("matches captured reference ids", async () => {
    expect(await portalId("0", "0")).toBe("W9|]XZ7:ruD{");
    expect(await portalId("35.681236", "139.767125")).toBe("v/L|,tfHsY05");
  });
});
