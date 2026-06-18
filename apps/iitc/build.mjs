// Builds the IITC userscript from the TypeScript sources.
//
// Output (dist/):
//   damage-report-plots.user.js  metablock + wrapper(plugin_info) + bundled body
//   damage-report-plots.meta.js  metablock only (served at @updateURL)
//
// IITC plugins must run in the page context, not the userscript sandbox, so the
// bundled body is inlined inside a `wrapper(plugin_info)` function which a small
// bootstrap IIFE stringifies and injects via a <script> element. The bundle
// references `plugin_info` lexically (closure), so no globals are needed.

import * as esbuild from "esbuild";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const distDir = join(root, "dist");
const entry = join(root, "src", "plugin.ts");
const basename = "damage-report-plots";
const watch = process.argv.includes("--watch");

// Load metadata.ts (the metablock source of truth) by transpiling it to ESM and
// importing it from a data: URL — keeps a single TS source without a TS loader.
async function loadMetadata() {
  const result = await esbuild.build({
    entryPoints: [join(root, "src", "metadata.ts")],
    bundle: true,
    format: "esm",
    platform: "node",
    write: false,
  });
  const code = result.outputFiles[0].text;
  const mod = await import(
    "data:text/javascript;base64," + Buffer.from(code).toString("base64")
  );
  return { metadata: mod.metadata, repeatedKeys: mod.repeatedKeys ?? [] };
}

// A release build passes the git tag (e.g. iitc-v1.2.3) so the published version
// matches the tag; locally we fall back to the version baked into metadata.ts.
function resolveVersion(declared) {
  const raw = process.env.PLUGIN_VERSION;
  if (!raw) return declared;
  return raw.replace(/^iitc-v/, "").replace(/^v/, "");
}

function renderMetablock({ metadata, repeatedKeys }, version) {
  const entries = [];
  for (const [key, value] of Object.entries(metadata)) {
    entries.push([key, key === "version" ? version : value]);
  }
  for (const pair of repeatedKeys) entries.push(pair);

  const pad = Math.max(...entries.map(([k]) => k.length));
  const lines = entries.map(([k, v]) => `// @${k.padEnd(pad)}  ${v}`);
  return ["// ==UserScript==", ...lines, "// ==/UserScript=="].join("\n");
}

function renderUserScript(metablock, body) {
  // `wrapper` is emitted as a real function so the bootstrap can stringify it
  // with `'(' + wrapper + ')(...)'`; `body` is inlined inside it.
  return `${metablock}

function wrapper(plugin_info) {
  if (typeof window.plugin !== 'function') window.plugin = function () {};

${body}
}

(function () {
  var info = {};
  if (typeof GM_info !== 'undefined' && GM_info && GM_info.script) {
    info.script = {
      version: GM_info.script.version,
      name: GM_info.script.name,
      description: GM_info.script.description,
    };
  }
  var script = document.createElement('script');
  script.appendChild(
    document.createTextNode('(' + wrapper + ')(' + JSON.stringify(info) + ');')
  );
  (document.body || document.head || document.documentElement).appendChild(script);
})();
`;
}

async function emit(metaInfo, bundleCode) {
  const version = resolveVersion(metaInfo.metadata.version);
  const metablock = renderMetablock(metaInfo, version);
  await mkdir(distDir, { recursive: true });
  await writeFile(
    join(distDir, `${basename}.user.js`),
    renderUserScript(metablock, bundleCode),
  );
  await writeFile(join(distDir, `${basename}.meta.js`), metablock + "\n");
  console.log(`built ${basename}.user.js / ${basename}.meta.js (v${version})`);
}

const metaInfo = await loadMetadata();

const buildOptions = {
  entryPoints: [entry],
  bundle: true,
  format: "iife",
  target: "es2020",
  write: false,
};

if (watch) {
  const ctx = await esbuild.context({
    ...buildOptions,
    plugins: [
      {
        name: "emit-userscript",
        setup(build) {
          build.onEnd((result) => {
            const out = result.outputFiles?.[0];
            if (out) emit(metaInfo, out.text).catch(console.error);
          });
        },
      },
    ],
  });
  await ctx.watch();
  console.log("watching for changes…");
} else {
  const result = await esbuild.build(buildOptions);
  await emit(metaInfo, result.outputFiles[0].text);
}
