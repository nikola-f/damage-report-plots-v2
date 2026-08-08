// Port of apps/api/app/models/damage_report_record.rb.

import Sqids from "sqids";

export interface DamageReportRecord {
  name: string;
  latitude: string;
  longitude: string;
  owned: boolean;
  // Day-truncated report time in 100-second units (see truncateInternalDate in
  // decoder.ts). The spreadsheet packs this with the portal name in column E,
  // and dedupe uses it so same-day reports of a portal collapse.
  internalDate: number;
}

// Same alphabet as the Ruby SQIDS_ALPHABET (printable ASCII minus " and ').
const SQIDS_ALPHABET =
  "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&()*+,-./:;<=>?@[]^_`{|}~";
const sqids = new Sqids({ alphabet: SQIDS_ALPHABET });

// Deduplicate by name/latitude/longitude/internalDate; owned:true wins over
// owned:false, and first-occurrence order is preserved (Ruby: group_by + max_by).
export function deduplicate(records: DamageReportRecord[]): DamageReportRecord[] {
  const byKey = new Map<string, DamageReportRecord>();
  for (const r of records) {
    const key = JSON.stringify([r.name, r.latitude, r.longitude, r.internalDate]);
    const existing = byKey.get(key);
    if (!existing || (!existing.owned && r.owned)) byKey.set(key, r);
  }
  return [...byKey.values()];
}

// Stable per-portal grouping key for the spreadsheet's `reports` column A.
// SHA-256("lat,lng") → first 8 bytes big-endian → top 62 bits → Sqids.
//
// The 62-bit value exceeds JS's safe-integer range and the sqids library rejects
// numbers > 2^53, so it is split into two 31-bit chunks and encoded as an array.
// This is deterministic and reversible; the id differs from the retired Ruby
// pipeline's single-number encoding, which is fine because client-side sheets are
// created fresh (only intra-sheet consistency matters).
export async function portalId(latitude: string, longitude: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${latitude},${longitude}`),
  );
  const bytes = new Uint8Array(digest);
  let n = 0n;
  for (let i = 0; i < 8; i++) n = (n << 8n) | BigInt(bytes[i]);
  n &= (1n << 62n) - 1n;
  const hi = Number(n >> 31n);
  const lo = Number(n & 0x7fff_ffffn);
  return sqids.encode([hi, lo]);
}
