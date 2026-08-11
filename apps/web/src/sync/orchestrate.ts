// End-to-end client-side sync: resolve the user's single spreadsheet, resume
// from where the sheet left off, scan Gmail, append new reports, then read back
// the aggregated plots for the clipboard. Replaces the entire server pipeline
// (sync_controller + the three Sidekiq workers). No Gmail data touches a server.

import definition from "./spreadsheetDefinition.json";
import protection from "./spreadsheetProtection.json";
import { findOrCreateSpreadsheetId } from "./spreadsheet";
import { findSpreadsheetId } from "./drive";
import { readResumeSince, readSyncPointer, writeSyncPointer } from "./resume";
import { runSync, type SyncProgress } from "./engine";
import { defaultFetch, type FetchLike } from "./http";
import { appendRows, getValues } from "./sheets";
import { toReportRow, rowsToPlots, type Plot } from "./mapping";
import { DEFAULT_AFTER_DATE } from "./query";

const REPORTS_SHEET = "reports";
const PLOTS_RANGE = "plots!A:F";

export interface FullSyncOptions {
  accessToken: string;
  fetchFn?: FetchLike;
  onProgress?: (p: SyncProgress) => void;
  until?: number; // epoch seconds; default now (mainly for tests)
  now?: Date; // append-timestamp clock; injectable for tests
}

export interface FullSyncResult {
  spreadsheetId: string;
  appended: number; // number of report rows written this run
  truncated: boolean; // true when the run hit the thread cap; sync again to continue
}

// Discover the user's existing spreadsheet (id) without creating one, so the UI
// can enable Copy after a fresh login even when no sync ran this session. Returns
// null if the user has never synced. Works across devices via drive.file.
export async function findSpreadsheet(
  accessToken: string,
  fetchFn: FetchLike = defaultFetch,
): Promise<string | null> {
  return findSpreadsheetId(accessToken, fetchFn);
}

// Read the aggregated plots for the clipboard. Kept separate from runFullSync so
// the UI reads on the Copy click — after the sheet's QUERY has recalculated from
// this run's (possibly large) append, and as an explicit user-gesture request.
export async function readPlots(
  accessToken: string,
  spreadsheetId: string,
  fetchFn: FetchLike = defaultFetch,
): Promise<Plot[]> {
  return rowsToPlots(await getValues(accessToken, spreadsheetId, PLOTS_RANGE, fetchFn));
}

export async function runFullSync(options: FullSyncOptions): Promise<FullSyncResult> {
  const fetchFn = options.fetchFn ?? defaultFetch;
  const { accessToken } = options;

  const { spreadsheetId } = await findOrCreateSpreadsheetId(
    accessToken,
    fetchFn,
    definition,
    protection,
  );

  const since = (await readResumeSince(accessToken, spreadsheetId, fetchFn)) ?? DEFAULT_AFTER_DATE;
  // Exact high-water mark of what's already in the sheet. `since` is only
  // day-granular, so without this the last day's messages are re-appended on
  // every sync. Absent on sheets created before the pointer existed.
  const sinceInternalDateMs = await readSyncPointer(accessToken, spreadsheetId, fetchFn);

  // Run-scoped high-water mark, seeded from the stored pointer. threads.get
  // returns every message in a thread regardless of the queried window, so an
  // early window can surface a message newer than anything in a later window;
  // writing each window's max unconditionally would then move the pointer
  // *backwards* mid-run and let the next sync re-append what is already in the
  // sheet. Advancing only forward mirrors the retired server's
  // GmailThreadBatchWorker#advance_resume_point guard.
  let pointer = sinceInternalDateMs ?? 0;

  // Append each window's reports as they're scanned, so an interrupted run keeps
  // its progress (and the sheet's resume point advances) instead of losing
  // everything.
  let appended = 0;
  const { truncated } = await runSync({
    accessToken,
    fetchFn,
    since,
    sinceInternalDateMs,
    until: options.until,
    onProgress: options.onProgress,
    onWindow: async (windowRecords, windowMaxInternalDate) => {
      const rows = await Promise.all(windowRecords.map((r) => toReportRow(r, options.now)));
      await appendRows(accessToken, spreadsheetId, REPORTS_SHEET, rows, fetchFn);
      appended += windowRecords.length;
      // Advance the pointer only after the rows are persisted, so an interrupted
      // run resumes from what actually landed in the sheet.
      if (windowMaxInternalDate > pointer) {
        pointer = windowMaxInternalDate;
        await writeSyncPointer(accessToken, spreadsheetId, pointer, fetchFn);
      }
    },
  });

  return { spreadsheetId, appended, truncated };
}
