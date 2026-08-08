// Port of apps/api/app/models/damage_report_query.rb.
// Builds the Gmail search query for Ingress Damage Report emails. Client-side
// only — the resulting string is passed straight to the Gmail REST API.

export const SUBJECT = "Ingress Damage Report: Entities attacked by";
export const FROM = [
  "ingress-support@google.com",
  "ingress-support@nianticlabs.com",
  "ingress-support@nianticspatial.com",
] as const;
export const LARGER = "5K";
export const SMALLER = "100K";

// 2012-10-15 UTC — earliest possible damage report (Ruby DEFAULT_AFTER_DATE).
export const DEFAULT_AFTER_DATE = Date.UTC(2012, 9, 15) / 1000;
export const DAYS_WINDOW = 30;

const SECONDS_PER_DAY = 86_400;

// Gmail's after:/before: operators are day-granular; Ruby aligns both bounds to
// UTC midnight (Time#to_date). Mirror that so identical windows produce
// identical queries.
function toMidnight(epochSeconds: number): number {
  return Math.floor(epochSeconds / SECONDS_PER_DAY) * SECONDS_PER_DAY;
}

export function buildQuery(afterEpoch: number, beforeEpoch: number): string {
  const after = toMidnight(afterEpoch);
  const before = toMidnight(beforeEpoch);
  const fromPart = `{${FROM.map((f) => `from:${f}`).join(" ")}}`;
  return `subject:${SUBJECT} after:${after} before:${before} ${fromPart} larger:${LARGER} smaller:${SMALLER}`;
}
