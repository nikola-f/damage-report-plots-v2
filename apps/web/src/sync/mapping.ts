// Bridges between extracted records, the spreadsheet's `reports` rows, and the
// `plots` output. Ports apps/api SpreadsheetSyncWorker#to_row and
// PlotsController#to_plot so the clipboard payload keeps the exact shape the
// IITC plugin's parsePlots expects ({lat, lng, count, latest, ...}).

import { portalId, type DamageReportRecord } from "./record";

// One row of the `reports` sheet:
// [hash, latitude, longitude, portalOwned(0|1), "mailDate,portalName", appendDate]
export type ReportRow = [string, number, number, number, string, number];

// Ruby: Time.now.strftime("%y%m%d%H%M%S").to_i (append bookkeeping column).
function appendStamp(now: Date): number {
  const p = (n: number) => String(n).padStart(2, "0");
  return Number(
    `${p(now.getUTCFullYear() % 100)}${p(now.getUTCMonth() + 1)}${p(now.getUTCDate())}` +
      `${p(now.getUTCHours())}${p(now.getUTCMinutes())}${p(now.getUTCSeconds())}`,
  );
}

export async function toReportRow(record: DamageReportRecord, now: Date = new Date()): Promise<ReportRow> {
  return [
    await portalId(record.latitude, record.longitude),
    Number(record.latitude),
    Number(record.longitude),
    record.owned ? 1 : 0,
    `${record.internalDate},${record.name}`,
    appendStamp(now),
  ];
}

// The plots payload copied to the clipboard (identical to the old
// GET /api/v1/plots response consumed by apps/iitc).
export interface Plot {
  lat: number;
  lng: number;
  owned: number;
  count: number;
  latest: number;
  oldest?: number; // omitted when count === 1 (blank in the sheet)
}

// Convert `plots!A:F` rows into Plot objects. Rows without numeric lat/lng are
// dropped — this also removes the QUERY's leading aggregate-label row and any
// trailing blanks, so the caller gets clean coordinate data.
export function rowsToPlots(rows: unknown[][]): Plot[] {
  return rows.flatMap((row) => {
    if (typeof row[0] !== "number" || typeof row[1] !== "number") return [];
    const plot: Plot = {
      lat: row[0],
      lng: row[1],
      owned: row[2] as number,
      count: row[3] as number,
      latest: row[4] as number,
    };
    const oldest = row[5];
    if (oldest !== undefined && oldest !== null && oldest !== "") plot.oldest = oldest as number;
    return [plot];
  });
}
