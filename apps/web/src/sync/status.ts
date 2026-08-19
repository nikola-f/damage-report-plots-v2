// Read-back summary for the post-login UI, sourced from the spreadsheet's `stats`
// named range so it's consistent across devices (no server). The range is a
// single column (see spreadsheetDefinition.json → stats sheet):
//   row 0: schema/version string
//   row 1: =COUNT(plots!C:C)          → total portals
//   row 2: =COUNTIF(plots!C:C, "=1")  → owned portals
//   row 3: =PERCENTILE(plots!D:D,…)   → (unused here)
//   row 4: =MIN(plots!F:F)            → oldest report time
//   row 5: =MAX(plots!E:E)            → latest report time
// Report times are day-truncated 100-second units; ×100 recovers epoch seconds
// (same convention as resume.ts).

import { getValues } from "./sheets";
import { defaultFetch, type FetchLike } from "./http";

export const STATS_NAMED_RANGE = "stats";

export interface SheetStats {
  portals: number;
  ownedPortals: number;
  latestReport?: number; // epoch seconds; undefined when the sheet has no data
  oldestReport?: number; // epoch seconds
}

function num(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

export async function readStats(
  token: string,
  spreadsheetId: string,
  fetchFn: FetchLike = defaultFetch,
): Promise<SheetStats> {
  const rows = await getValues(token, spreadsheetId, STATS_NAMED_RANGE, fetchFn);
  const cell = (i: number): unknown => rows[i]?.[0];
  const latest = num(cell(5));
  const oldest = num(cell(4));
  return {
    portals: num(cell(1)) ?? 0,
    ownedPortals: num(cell(2)) ?? 0,
    latestReport: latest && latest > 0 ? latest * 100 : undefined,
    oldestReport: oldest && oldest > 0 ? oldest * 100 : undefined,
  };
}
