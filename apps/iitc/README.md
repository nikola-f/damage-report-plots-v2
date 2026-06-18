# Damage Report Plots — IITC plugin

An [IITC](https://iitc.app/) (Ingress Intel Total Conversion) plugin that plots
this project's Ingress damage-report data on the Intel map.

> Status: scaffolding. The current build only adds a "Damage Report Plots" link
> to the IITC toolbox to prove the plugin loads. Map rendering of damage data is
> built on top of this.

## Layout

```
src/
  metadata.ts   UserScript metablock fields (single source of truth)
  plugin.ts     plugin body — registered into window.bootPlugins
  iitc.d.ts     minimal ambient types for the IITC runtime
build.mjs       esbuild bundle + wrapper + metablock → dist/*.user.js + *.meta.js
```

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
