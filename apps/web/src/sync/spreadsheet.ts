// Resolve the user's single damage-report spreadsheet: rediscover it on Drive
// (works across devices via the drive.file appProperties marker), or create and
// tag a fresh one. This is the client-side replacement for the server's
// ensure_spreadsheet_exists + Redis spreadsheet_id mapping.

import { findSpreadsheetId, tagSpreadsheet } from "./drive";
import { createSpreadsheet, protectRanges } from "./sheets";
import type { FetchLike } from "./http";

export interface ResolvedSpreadsheet {
  spreadsheetId: string;
  created: boolean; // true when a new spreadsheet was created this call
}

export async function findOrCreateSpreadsheetId(
  token: string,
  fetchFn: FetchLike,
  definition: unknown,
  protection?: { requests?: unknown[] },
): Promise<ResolvedSpreadsheet> {
  const existing = await findSpreadsheetId(token, fetchFn);
  if (existing) return { spreadsheetId: existing, created: false };

  const spreadsheetId = await createSpreadsheet(token, definition, fetchFn);
  if (protection) await protectRanges(token, spreadsheetId, protection, fetchFn);
  await tagSpreadsheet(token, spreadsheetId, fetchFn);
  return { spreadsheetId, created: true };
}
