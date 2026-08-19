// Drive API access via the non-sensitive drive.file scope. Used to keep ONE
// spreadsheet per user across devices: the app tags the spreadsheet it creates
// with a private appProperty, then any device rediscovers it with files.list.
// drive.file only ever exposes files this app created — no broad Drive access.

import type { FetchLike } from "./http";

export const DRIVE_BASE = "https://www.googleapis.com/drive/v3";
export const SHEET_MIME = "application/vnd.google-apps.spreadsheet";

// Private (app-only) marker written to appProperties so rename/move can't hide
// the file and other apps can't see the key.
export const MARKER_KEY = "drpSheet";
export const MARKER_VALUE = "1";

// Find the app's damage-report spreadsheet. Returns the oldest match (stable
// choice if two devices raced and created duplicates), or null if none exists.
export async function findSpreadsheetId(token: string, fetchFn: FetchLike): Promise<string | null> {
  const q =
    `appProperties has { key='${MARKER_KEY}' and value='${MARKER_VALUE}' } ` +
    `and mimeType='${SHEET_MIME}' and trashed=false`;
  const url = new URL(`${DRIVE_BASE}/files`);
  url.searchParams.set("q", q);
  url.searchParams.set("fields", "files(id,createdTime)");
  url.searchParams.set("orderBy", "createdTime"); // oldest first
  url.searchParams.set("pageSize", "1");

  const res = await fetchFn(url.toString(), { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`drive files.list ${res.status}`);
  const data = (await res.json()) as { files?: { id: string }[] };
  return data.files?.[0]?.id ?? null;
}

// Tag a freshly-created spreadsheet so future devices can rediscover it.
export async function tagSpreadsheet(
  token: string,
  spreadsheetId: string,
  fetchFn: FetchLike,
): Promise<void> {
  const res = await fetchFn(`${DRIVE_BASE}/files/${encodeURIComponent(spreadsheetId)}`, {
    method: "PATCH",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ appProperties: { [MARKER_KEY]: MARKER_VALUE } }),
  });
  if (!res.ok) throw new Error(`drive files.update ${res.status}`);
}
