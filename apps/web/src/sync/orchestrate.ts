// End-to-end client-side sync: resolve the user's single spreadsheet, resume
// from where the sheet left off, scan Gmail, append new reports, then read back
// the aggregated plots for the clipboard. Replaces the entire server pipeline
// (sync_controller + the three Sidekiq workers). No Gmail data touches a server.

import definition from "./spreadsheetDefinition.json";
import protection from "./spreadsheetProtection.json";
import { findOrCreateSpreadsheetId } from "./spreadsheet";
import { readResumeSince } from "./resume";
import { runSync, type FetchLike, type SyncProgress } from "./engine";
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
  plots: Plot[]; // clipboard payload (same shape as the old GET /api/v1/plots)
  appended: number; // number of report rows written this run
}

export async function runFullSync(options: FullSyncOptions): Promise<FullSyncResult> {
  const fetchFn = options.fetchFn ?? fetch;
  const { accessToken } = options;

  const { spreadsheetId } = await findOrCreateSpreadsheetId(
    accessToken,
    fetchFn,
    definition,
    protection,
  );

  const since = (await readResumeSince(accessToken, spreadsheetId, fetchFn)) ?? DEFAULT_AFTER_DATE;

  const { records } = await runSync({
    accessToken,
    fetchFn,
    since,
    until: options.until,
    onProgress: options.onProgress,
  });

  if (records.length > 0) {
    const rows = await Promise.all(records.map((r) => toReportRow(r, options.now)));
    await appendRows(accessToken, spreadsheetId, REPORTS_SHEET, rows, fetchFn);
  }

  const plots = rowsToPlots(await getValues(accessToken, spreadsheetId, PLOTS_RANGE, fetchFn));
  return { spreadsheetId, plots, appended: records.length };
}
