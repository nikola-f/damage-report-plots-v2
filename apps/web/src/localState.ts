// Per-device sync bookkeeping in localStorage. The spreadsheet holds the shared,
// cross-device state (see sync/status.ts); this records only what is inherently
// local — when this browser last ran a sync and how many reports it added.
// Keyed by spreadsheet id so switching accounts/sheets doesn't cross wires.

export interface LastSync {
  at: number; // epoch ms of the last successful sync on this device
  appended: number; // reports written that run
}

const key = (spreadsheetId: string) => `drp:lastSync:${spreadsheetId}`;

export function loadLastSync(spreadsheetId: string): LastSync | null {
  try {
    const raw = localStorage.getItem(key(spreadsheetId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<LastSync>;
    if (typeof parsed.at !== "number") return null;
    return { at: parsed.at, appended: typeof parsed.appended === "number" ? parsed.appended : 0 };
  } catch {
    return null; // storage disabled or malformed
  }
}

export function saveLastSync(spreadsheetId: string, value: LastSync): void {
  try {
    localStorage.setItem(key(spreadsheetId), JSON.stringify(value));
  } catch {
    // Ignore: private mode / storage full / disabled. The spreadsheet stays the
    // source of truth; only the local "last synced" hint is lost.
  }
}
