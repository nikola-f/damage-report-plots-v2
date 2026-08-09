// Resume point, sourced from the spreadsheet so it stays consistent across
// devices (no server, no local-only state). The sheet's `lastReportTime` named
// range is =MAX(plots!E:E): the newest report time in day-truncated 100-second
// units (see truncateInternalDate). Multiplying by 100 recovers a day-aligned
// epoch-seconds bound; the sync re-scans at most that last day and dedupe
// collapses the overlap.

import { getValues } from "./sheets";
import type { FetchLike } from "./http";

export const RESUME_NAMED_RANGE = "lastReportTime";

export async function readResumeSince(
  token: string,
  spreadsheetId: string,
  fetchFn: FetchLike,
): Promise<number | undefined> {
  const rows = await getValues(token, spreadsheetId, RESUME_NAMED_RANGE, fetchFn);
  const value = rows[0]?.[0];
  if (typeof value !== "number" || value <= 0) return undefined;
  return value * 100; // 100-second units → epoch seconds (start of that UTC day)
}
