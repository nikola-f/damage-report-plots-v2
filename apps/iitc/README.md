# Damage Report Plots — IITC plugin

An [IITC](https://iitc.app/) (Ingress Intel Total Conversion) plugin that renders
this project's Ingress damage-report data as a **heatmap** on the Intel map.

The plugin takes its data by **paste**: copy the plots JSON from the web app
("Copy plots JSON") and paste it into the plugin's dialog. Nothing is fetched over
the network, so no API CORS changes or cross-site authentication are needed.

## Usage

1. In the web app, click **Copy plots JSON** to put the plots array on your clipboard.
2. On the Intel map, open the **Damage Report Plots** entry in the IITC toolbox.
3. Paste the JSON into the textarea, pick a weight, and click **Plot**.
   - **Weight: report count** — hotter where more damage reports accumulated.
   - **Weight: recency (latest)** — hotter where the most recent reports are.
   - Switching the weight re-renders instantly (no need to re-paste).
4. Toggle the **Damage Report Plots** layer from IITC's layer chooser.

The pasted data and weight are saved to `localStorage`, so the heatmap is restored
automatically after a page reload. Use **Clear** to remove it.

## Layout

```
src/
  metadata.ts   UserScript metablock fields (single source of truth)
  plugin.ts     plugin body (UI + heat layer) — registered into window.bootPlugins
  plots.ts      pure logic: parse pasted JSON + normalize to heat points
  heat.ts       lazy loader for the bundled leaflet.heat plugin
  iitc.d.ts     minimal ambient types for the IITC runtime (incl. Leaflet `L`)
build.mjs       esbuild bundle + wrapper + metablock → dist/*.user.js + *.meta.js
```

The heatmap is drawn with [leaflet.heat](https://github.com/Leaflet/Leaflet.heat),
bundled into the userscript and run against the Leaflet (`L`) that IITC provides.

## Build

```bash
npm install
npm run build       # → dist/damage-report-plots.user.js (+ .meta.js)
npm run dev         # rebuild on change
npm run typecheck   # tsc --noEmit
```

The build bundles `src/plugin.ts`, inlines it inside an IITC `wrapper(plugin_info)`
function (so it runs in the page context), and prepends the `// ==UserScript==`
metablock generated from `src/metadata.ts`.

## Install (development)

1. Install a userscript manager (Tampermonkey/Violentmonkey) and IITC-CE.
2. Open `dist/damage-report-plots.user.js` in the browser and install it.
3. Reload the Intel map — a "Damage Report Plots" entry appears in the toolbox.

## Release / distribution

Distribution is via **GitHub Releases** (no S3 deploy). Pushing a tag matching
`iitc-v*` triggers `.github/workflows/release-iitc.yml`, which builds and attaches
`damage-report-plots.user.js` and `.meta.js` to the release. The metablock's
`@downloadURL` / `@updateURL` point at `releases/latest/download/...`, so users
install and auto-update from the latest release.

```bash
git tag iitc-v0.1.0
git push origin iitc-v0.1.0
```
