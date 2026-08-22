// Resolve the user's single damage-report spreadsheet: rediscover it on Drive
// (works across devices via the drive.file appProperties marker), or create and
// tag a fresh one. This is the client-side replacement for the server's
// ensure_spreadsheet_exists + Redis spreadsheet_id mapping.

import { findSpreadsheetId, findUntaggedSpreadsheetId, tagSpreadsheet } from "./drive";
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

  // Before creating, look for a spreadsheet this app made but never tagged.
  // The marker is written after creation, so a failure in between — a dropped
  // connection, a 503 like the one the first production sync hit — leaves a
  // real spreadsheet that findSpreadsheetId can never see again. Creating a
  // second one would strand the first's data permanently, since drive.file
  // offers no other way back to it. Adopting it costs one extra read on the
  // very first sync only.
  const untagged = await findUntaggedSpreadsheetId(token, fetchFn);
  if (untagged) {
    await tagSpreadsheet(token, untagged, fetchFn);
    return { spreadsheetId: untagged, created: false };
  }

  const spreadsheetId = await createSpreadsheet(token, definition, fetchFn);
  if (protection) await protectRanges(token, spreadsheetId, protection, fetchFn);
  await tagSpreadsheet(token, spreadsheetId, fetchFn);
  return { spreadsheetId, created: true };
}
