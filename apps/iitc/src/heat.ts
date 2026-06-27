// Lazily loads the bundled leaflet.heat plugin.
//
// leaflet.heat has no exports — it references the page global `L` at evaluation
// time and attaches `L.heatLayer`. IITC only defines `L` after its core boots, so
// an eager `import "leaflet.heat"` would run at the userscript wrapper's top level
// (before `L` exists) and throw "L is not defined". Using CommonJS `require` keeps
// the module in an esbuild __commonJS wrapper that is evaluated only on first call,
// which we make from setup() — by then IITC has defined `L`.

let loaded = false;

export function ensureHeatLayer(): void {
  if (loaded) return;
  // Honest runtime check: the ambient type says heatLayer is always present, but
  // it only exists once the module below has run.
  if (typeof (L as { heatLayer?: unknown }).heatLayer === "function") {
    loaded = true;
    return;
  }
  require("leaflet.heat");
  loaded = true;
}
