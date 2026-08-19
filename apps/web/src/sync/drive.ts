// Drive API access via the non-sensitive drive.file scope. Used to keep ONE
// spreadsheet per user across devices: the app tags the spreadsheet it creates
// with a private appProperty, then any device rediscovers it with files.list.
// drive.file only ever exposes files this app created — no broad Drive access.

import type { FetchLike } from "./http";
import { withRetry, apiError, type RetryOptions } from "./retry";

export const DRIVE_BASE = "https://www.googleapis.com/drive/v3";
export const SHEET_MIME = "application/vnd.google-apps.spreadsheet";

// Private (app-only) marker written to appProperties so rename/move can't hide
// the file and other apps can't see the key.
export const MARKER_KEY = "drpSheet";
export const MARKER_VALUE = "1";

// Both lookups are plain reads, so retrying a transient failure is free.
async function listOldestSpreadsheet(
  token: string,
  q: string,
  fetchFn: FetchLike,
  retry: RetryOptions,
): Promise<string | null> {
  const url = new URL(`${DRIVE_BASE}/files`);
  url.searchParams.set("q", q);
  url.searchParams.set("fields", "files(id,createdTime)");
  url.searchParams.set("orderBy", "createdTime"); // oldest first
  url.searchParams.set("pageSize", "1");

  return withRetry(async () => {
    const res = await fetchFn(url.toString(), { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw await apiError(res, "drive files.list");
    const data = (await res.json()) as { files?: { id: string }[] };
    return data.files?.[0]?.id ?? null;
  }, retry);
}

// Find the app's damage-report spreadsheet. Returns the oldest match (stable
// choice if two devices raced and created duplicates), or null if none exists.
export async function findSpreadsheetId(
  token: string,
  fetchFn: FetchLike,
  retry: RetryOptions = {},
): Promise<string | null> {
  const q =
    `appProperties has { key='${MARKER_KEY}' and value='${MARKER_VALUE}' } ` +
    `and mimeType='${SHEET_MIME}' and trashed=false`;
  return listOldestSpreadsheet(token, q, fetchFn, retry);
}

// Same search without the marker, used only to recover a spreadsheet that was
// created but never tagged — see findOrCreateSpreadsheetId. This is safe
// precisely because the scope is drive.file: it exposes only files this app
// created, so anything it returns is ours and no other app's spreadsheet can
// be adopted by mistake.
export async function findUntaggedSpreadsheetId(
  token: string,
  fetchFn: FetchLike,
  retry: RetryOptions = {},
): Promise<string | null> {
  return listOldestSpreadsheet(
    token,
    `mimeType='${SHEET_MIME}' and trashed=false`,
    fetchFn,
    retry,
  );
}

// Tag a freshly-created spreadsheet so future devices can rediscover it.
// Retried because it sets a fixed value: repeating it produces the same file.
// Worth retrying rather than failing, since a spreadsheet that exists without
// its marker is invisible to the next sync, which would then create a second.
export async function tagSpreadsheet(
  token: string,
  spreadsheetId: string,
  fetchFn: FetchLike,
  retry: RetryOptions = {},
): Promise<void> {
  await withRetry(async () => {
    const res = await fetchFn(`${DRIVE_BASE}/files/${encodeURIComponent(spreadsheetId)}`, {
      method: "PATCH",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ appProperties: { [MARKER_KEY]: MARKER_VALUE } }),
    });
    if (!res.ok) throw await apiError(res, "drive files.update");
  }, retry);
}
