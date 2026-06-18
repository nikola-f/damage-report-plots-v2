// Single source of truth for the UserScript metadata block. build.mjs reads
// this to render the `// ==UserScript== … ==/UserScript==` header that prepends
// both the .user.js bundle and the .meta.js update stub. Keep keys in the order
// they should appear in the generated header.
//
// @version is intentionally a fixed string here; the release workflow can
// override it from the git tag at build time (see build.mjs / release-iitc.yml).

const REPO = "https://github.com/nikola-f/damage-report-plots-v2";

export const metadata: Record<string, string> = {
  id: "damage-report-plots@nikola-f",
  name: "IITC plugin: Damage Report Plots",
  category: "Layer",
  version: "0.0.0",
  namespace: REPO,
  description: "Plot Ingress damage report data on the Intel map.",
  match: "https://intel.ingress.com/*",
  downloadURL: `${REPO}/releases/latest/download/damage-report-plots.user.js`,
  updateURL: `${REPO}/releases/latest/download/damage-report-plots.meta.js`,
  grant: "none",
};

// A few keys legitimately repeat in a metadata block (e.g. multiple @match).
// They are emitted in addition to the single-valued `metadata` map above.
export const repeatedKeys: ReadonlyArray<[string, string]> = [
  ["match", "https://*.ingress.com/intel*"],
];
