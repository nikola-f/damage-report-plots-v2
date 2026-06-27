// Plugin body. esbuild bundles this into a string that build.mjs inlines inside
// the userscript `wrapper(plugin_info)` function, so `plugin_info` resolves via
// closure at runtime (declared ambient in iitc.d.ts).
//
// Renders the project's plots data as a heatmap on the Ingress Intel map. The
// data is pasted in (the array copied by the web app's "Copy plots JSON" button),
// so the plugin needs no network access or auth — see README.md.

import { ensureHeatLayer } from "./heat";
import { parsePlots, toHeatPoints, type Plot, type Weight } from "./plots";

const STORAGE_KEY = "damage-report-plots";
// leaflet.heat scales intensity by 1 / 2^(maxZoom - currentZoom), so without a
// maxZoom it fades against the map's max zoom (~21 on Intel) and stays faint even
// when zoomed in. Capping maxZoom at a typical viewing zoom makes intensity reach
// full there; the larger radius / minOpacity floor keep isolated low-count points
// visible once portals spread apart at high zoom.
const HEAT_OPTIONS: HeatMapOptions = { max: 1, radius: 30, blur: 20, minOpacity: 0.25, maxZoom: 17 };

interface StoredState {
  json: string;
  weight: Weight;
}

let heatLayer: HeatLayer | null = null;
let plots: Plot[] = [];
let weight: Weight = "count";

function loadState(): StoredState | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<StoredState>;
    if (typeof parsed.json !== "string") return null;
    return { json: parsed.json, weight: parsed.weight === "latest" ? "latest" : "count" };
  } catch {
    return null;
  }
}

function saveState(json: string): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ json, weight } satisfies StoredState));
  } catch {
    // localStorage unavailable or over quota — persistence is best-effort.
  }
}

// Push the current plots/weight into the heat layer. Safe before the layer is on
// the map: leaflet.heat's redraw no-ops until its canvas is initialized.
function render(): void {
  heatLayer?.setLatLngs(toHeatPoints(plots, weight));
}

function readWeight(value: string): Weight {
  return value === "latest" ? "latest" : "count";
}

function openDialog(): void {
  const container = document.createElement("div");

  const textarea = document.createElement("textarea");
  textarea.placeholder = "Paste plots JSON copied from the web app…";
  textarea.style.width = "100%";
  textarea.style.height = "8em";
  textarea.value = loadState()?.json ?? "";
  container.appendChild(textarea);

  const controls = document.createElement("div");
  controls.style.marginTop = "0.5em";

  const select = document.createElement("select");
  const options: ReadonlyArray<[Weight, string]> = [
    ["count", "Weight: report count"],
    ["latest", "Weight: recency (latest)"],
  ];
  for (const [value, label] of options) {
    const opt = document.createElement("option");
    opt.value = value;
    opt.textContent = label;
    if (value === weight) opt.selected = true;
    select.appendChild(opt);
  }
  controls.appendChild(select);

  const plotBtn = document.createElement("button");
  plotBtn.textContent = "Plot";
  const clearBtn = document.createElement("button");
  clearBtn.textContent = "Clear";
  const status = document.createElement("span");
  status.style.marginLeft = "0.75em";
  controls.append(plotBtn, clearBtn, status);
  container.appendChild(controls);

  const setStatus = (message: string, error = false) => {
    status.style.color = error ? "#fb4" : "";
    status.textContent = message;
  };

  // Re-weighting already-loaded data is instant; no re-paste needed.
  select.addEventListener("change", () => {
    weight = readWeight(select.value);
    if (plots.length > 0) {
      render();
      saveState(textarea.value);
    }
  });

  plotBtn.addEventListener("click", () => {
    try {
      plots = parsePlots(textarea.value);
      weight = readWeight(select.value);
      render();
      saveState(textarea.value);
      setStatus(`Plotted ${plots.length} points.`);
    } catch (e) {
      setStatus(e instanceof Error ? e.message : "Invalid JSON.", true);
    }
  });

  clearBtn.addEventListener("click", () => {
    plots = [];
    render();
    textarea.value = "";
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {
      // ignore
    }
    setStatus("Cleared.");
  });

  if (window.dialog) {
    window.dialog({
      title: "Damage Report Plots",
      html: container,
      id: "damage-report-plots",
      width: 420,
    });
  } else {
    // Fallback for environments without IITC's dialog (e.g. manual testing).
    document.body.appendChild(container);
  }
}

const setup: IITCSetup = function () {
  ensureHeatLayer();
  heatLayer = L.heatLayer([], HEAT_OPTIONS);
  window.addLayerGroup?.("Damage Report Plots", heatLayer, true);

  // Restore the last pasted dataset so the heatmap survives a page reload.
  const stored = loadState();
  if (stored) {
    weight = stored.weight;
    try {
      plots = parsePlots(stored.json);
      render();
    } catch {
      // Stored data no longer parses; start empty.
    }
  }

  const link = document.createElement("a");
  link.textContent = "Damage Report Plots";
  link.title = "Plot damage report data as a heatmap";
  link.addEventListener("click", openDialog);
  const toolbox = document.getElementById("toolbox");
  if (toolbox) toolbox.appendChild(link);

  console.log("[damage-report-plots] plugin loaded", plugin_info?.script?.version);
};

setup.info = plugin_info;
if (!window.bootPlugins) window.bootPlugins = [];
window.bootPlugins.push(setup);
// If IITC has already finished booting (plugin loaded late), run immediately.
if (window.iitcLoaded) setup();
