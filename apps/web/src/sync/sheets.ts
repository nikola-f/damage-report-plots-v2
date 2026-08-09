// Port of apps/api/lib/spreadsheets_client.rb. Runs client-side against the
// Sheets REST API using the drive.file scope (accepted by spreadsheets.create
// for app-created files). `fetchFn` is injectable for tests.

import type { FetchLike } from "./http";

export const SHEETS_BASE = "https://sheets.googleapis.com/v4";

// Percent-encode one path segment. encodeURIComponent leaves "!" alone, but the
// A1 range separator must be encoded in the path, so encode it explicitly
// (matches Ruby's ERB::Util.url_encode).
function seg(value: string): string {
  return encodeURIComponent(value).replace(/!/g, "%21");
}

async function ok(res: Response, label: string): Promise<Response> {
  if (!res.ok) throw new Error(`${label} ${res.status}`);
  return res;
}

// Create a spreadsheet from a full definition body; returns the new id.
export async function createSpreadsheet(
  token: string,
  definition: unknown,
  fetchFn: FetchLike,
): Promise<string> {
  const res = await ok(
    await fetchFn(`${SHEETS_BASE}/spreadsheets`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(definition),
    }),
    "spreadsheets.create",
  );
  const data = (await res.json()) as { spreadsheetId?: string };
  if (!data.spreadsheetId) throw new Error("spreadsheets.create returned no id");
  return data.spreadsheetId;
}

// Apply protected ranges via batchUpdate. No-op when there are no requests.
export async function protectRanges(
  token: string,
  spreadsheetId: string,
  protection: { requests?: unknown[] },
  fetchFn: FetchLike,
): Promise<void> {
  if (!protection.requests || protection.requests.length === 0) return;
  await ok(
    await fetchFn(`${SHEETS_BASE}/spreadsheets/${seg(spreadsheetId)}:batchUpdate`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(protection),
    }),
    "spreadsheets.batchUpdate",
  );
}

// Read a range; UNFORMATTED_VALUE keeps numbers as numbers. Empty range → [].
export async function getValues(
  token: string,
  spreadsheetId: string,
  range: string,
  fetchFn: FetchLike,
): Promise<unknown[][]> {
  const url =
    `${SHEETS_BASE}/spreadsheets/${seg(spreadsheetId)}/values/${seg(range)}` +
    `?valueRenderOption=UNFORMATTED_VALUE`;
  const res = await ok(
    await fetchFn(url, { headers: { Authorization: `Bearer ${token}` } }),
    "spreadsheets.values.get",
  );
  if (res.status === 204) return []; // no content → treat as an empty range
  const data = (await res.json()) as { values?: unknown[][] };
  return data.values ?? [];
}

// Append rows to the end of a sheet (RAW so strings aren't reinterpreted).
export async function appendRows(
  token: string,
  spreadsheetId: string,
  sheetName: string,
  rows: unknown[][],
  fetchFn: FetchLike,
): Promise<void> {
  const url =
    `${SHEETS_BASE}/spreadsheets/${seg(spreadsheetId)}/values/${seg(`${sheetName}!A1`)}:append` +
    `?valueInputOption=RAW`;
  await ok(
    await fetchFn(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ values: rows }),
    }),
    "spreadsheets.values.append",
  );
}
