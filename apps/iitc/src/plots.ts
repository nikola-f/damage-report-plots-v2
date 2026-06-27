// Pure logic for turning pasted plots JSON into leaflet.heat input. No DOM / IITC
// dependencies so it stays easy to reason about and test.
//
// The input is the array produced by the web app's "Copy plots JSON" button
// (GET /api/v1/plots): one object per portal. See apps/web/src/api.ts.

export interface Plot {
  lat: number;
  lng: number;
  count: number; // number of damage reports at this portal
  latest: number; // epoch ms of the most recent report
}

// Which field drives heatmap intensity.
export type Weight = "count" | "latest";

// Parse and validate pasted JSON. Throws (with a human-readable message) on
// anything that isn't an array of objects carrying numeric lat/lng.
export function parsePlots(text: string): Plot[] {
  const data: unknown = JSON.parse(text);
  if (!Array.isArray(data)) {
    throw new Error("Expected a JSON array of plots.");
  }
  return data.map((item, i) => {
    if (typeof item !== "object" || item === null) {
      throw new Error(`Row ${i}: expected an object.`);
    }
    const row = item as Record<string, unknown>;
    if (typeof row.lat !== "number" || typeof row.lng !== "number") {
      throw new Error(`Row ${i}: lat and lng must be numbers.`);
    }
    return {
      lat: row.lat,
      lng: row.lng,
      count: typeof row.count === "number" ? row.count : 1,
      latest: typeof row.latest === "number" ? row.latest : 0,
    };
  });
}

// Convert plots to [lat, lng, intensity] with intensity normalized to 0..1.
//   count : intensity = count / maxCount  (more reports → hotter)
//   latest: intensity = (latest - min) / (max - min)  (more recent → hotter)
// Guards against an empty set, a zero range (all equal / single point), and large
// arrays (min/max via a loop rather than spreading into Math.max).
export function toHeatPoints(plots: Plot[], weight: Weight): HeatPoint[] {
  if (plots.length === 0) return [];

  let min = Infinity;
  let max = -Infinity;
  for (const p of plots) {
    const v = weight === "count" ? p.count : p.latest;
    if (v < min) min = v;
    if (v > max) max = v;
  }
  const range = max - min;

  return plots.map((p) => {
    const v = weight === "count" ? p.count : p.latest;
    let intensity: number;
    if (weight === "count") {
      intensity = max > 0 ? v / max : 1;
    } else {
      intensity = range > 0 ? (v - min) / range : 1;
    }
    return [p.lat, p.lng, intensity];
  });
}
