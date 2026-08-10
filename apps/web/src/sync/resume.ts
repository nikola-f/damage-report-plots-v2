// Resume point, sourced from the spreadsheet so it stays consistent across
// devices (no server, no local-only state). The sheet's `lastReportTime` named
// range is =MAX(plots!E:E): the newest report time in day-truncated 100-second
// units (see truncateInternalDate). Multiplying by 100 recovers a day-aligned
// epoch-seconds bound; the sync re-scans at most that last day and dedupe
// collapses the overlap.

import { getValues, updateValues } from "./sheets";
import { defaultFetch, type FetchLike } from "./http";

export const RESUME_NAMED_RANGE = "lastReportTime";

// Precise resume pointer: the raw Gmail internalDate (ms) high-water mark of the
// messages already written to the sheet. `lastReportTime` alone is day-truncated,
// so resuming from it re-reads the whole last day and re-appends messages that
// were already recorded (inflating the plots `count`). This cell keeps the exact
// point so the overlap day can be re-queried — Gmail's after: is day-granular —
// while already-processed messages are filtered out.
//
// Stored in the stats sheet at A7, just below the `stats` named range (A1:A6),
// so readStats is unaffected. The stats sheet is 1 column with the default 1000
// rows, so A7 already exists on sheets created before this change: an empty cell
// simply means "no precise pointer yet" and the day-truncated fallback is used.
// Sheet protection is warningOnly, so API writes are allowed.
export const SYNC_POINTER_RANGE = "stats!A7";

export async function readSyncPointer(
  token: string,
  spreadsheetId: string,
  fetchFn: FetchLike = defaultFetch,
): Promise<number | undefined> {
  const rows = await getValues(token, spreadsheetId, SYNC_POINTER_RANGE, fetchFn);
  const value = rows[0]?.[0];
  if (typeof value !== "number" || value <= 0) return undefined;
  return value;
}

export async function writeSyncPointer(
  token: string,
  spreadsheetId: string,
  internalDateMs: number,
  fetchFn: FetchLike = defaultFetch,
): Promise<void> {
  await updateValues(token, spreadsheetId, SYNC_POINTER_RANGE, [[internalDateMs]], fetchFn);
}

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
