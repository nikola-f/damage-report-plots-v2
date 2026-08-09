import { describe, it, expect } from "vitest";
import { toReportRow, rowsToPlots } from "./mapping";
import type { DamageReportRecord } from "./record";

describe("toReportRow", () => {
  it("maps a record to a reports row (hash, lat, lng, owned, packed date+name, stamp)", async () => {
    const record: DamageReportRecord = {
      name: "Alpha",
      latitude: "35.1",
      longitude: "139.2",
      owned: true,
      internalDate: 16_999_200,
    };
    const now = new Date(Date.UTC(2024, 0, 2, 3, 4, 5)); // 2024-01-02 03:04:05Z
    const row = await toReportRow(record, now);

    expect(typeof row[0]).toBe("string"); // portal id
    expect(row[1]).toBe(35.1);
    expect(row[2]).toBe(139.2);
    expect(row[3]).toBe(1); // owned → 1
    expect(row[4]).toBe("16999200,Alpha"); // "mailDate,portalName"
    expect(row[5]).toBe(240102030405); // yymmddHHMMSS
  });

  it("encodes owned:false as 0", async () => {
    const row = await toReportRow(
      { name: "B", latitude: "1", longitude: "2", owned: false, internalDate: 1 },
      new Date(Date.UTC(2024, 0, 1)),
    );
    expect(row[3]).toBe(0);
  });
});

describe("rowsToPlots", () => {
  it("keeps only numeric-coordinate rows and maps the columns", () => {
    const rows: unknown[][] = [
      ["max ", "count ", "", "", "", ""], // QUERY label row → dropped
      [35.1, 139.2, 1, 5, 16_999_200, 16_990_000],
      [10, 20, 0, 1, 16_999_200, ""], // count 1 → oldest omitted
      ["", "", "", "", "", ""], // trailing blank → dropped
    ];
    const plots = rowsToPlots(rows);

    expect(plots).toEqual([
      { lat: 35.1, lng: 139.2, owned: 1, count: 5, latest: 16_999_200, oldest: 16_990_000 },
      { lat: 10, lng: 20, owned: 0, count: 1, latest: 16_999_200 },
    ]);
  });
});
