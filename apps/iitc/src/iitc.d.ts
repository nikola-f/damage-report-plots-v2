// Minimal ambient declarations for the IITC plugin runtime. IITC injects the
// plugin into the page context, where these globals are provided by the IITC
// boot framework. Only the surface this scaffold touches is declared; extend as
// the plugin grows (e.g. window.map, window.portals, the Leaflet `L` global).

// Metadata passed by the userscript wrapper into the plugin's setup function.
// Mirrors the subset of GM_info.script forwarded in build.mjs.
interface PluginInfo {
  script?: {
    version?: string;
    name?: string;
    description?: string;
  };
}

// Provided by the userscript wrapper as a closure-scoped argument; the bundled
// plugin body is inlined inside `wrapper(plugin_info)`, so this resolves
// lexically at runtime. Declared as ambient so plugin.ts can reference it.
declare const plugin_info: PluginInfo;

// IITC setup callbacks are plain functions tagged with their plugin info.
type IITCSetup = (() => void) & { info?: PluginInfo };

// --- Leaflet / leaflet.heat ---------------------------------------------------
// IITC bundles Leaflet and exposes it as the page global `L`. The leaflet.heat
// plugin (bundled by this build) augments it with `L.heatLayer`. Only the surface
// this plugin uses is declared.

// A heatmap point: [lat, lng, intensity]. intensity is normalized to 0..1.
type HeatPoint = [number, number, number];

interface HeatMapOptions {
  max?: number;
  radius?: number;
  blur?: number;
  minOpacity?: number;
  maxZoom?: number;
  gradient?: Record<number, string>;
}

// The layer returned by L.heatLayer (a Leaflet layer; only setLatLngs is used).
interface HeatLayer {
  setLatLngs(latlngs: HeatPoint[]): HeatLayer;
}

interface LeafletStatic {
  heatLayer(latlngs: HeatPoint[], options?: HeatMapOptions): HeatLayer;
}

// Page global provided by IITC after its core boots (and L.heatLayer once the
// lazily-loaded leaflet.heat module has run — see heat.ts).
declare const L: LeafletStatic;

// CommonJS require, used to lazily evaluate leaflet.heat after `L` exists. esbuild
// resolves/bundles this at build time (kept lazy via a __commonJS wrapper).
declare function require(id: string): unknown;

// --- IITC runtime helpers -----------------------------------------------------
interface IITCDialogOptions {
  title?: string;
  html?: string | HTMLElement;
  id?: string;
  width?: number | string;
  dialogClass?: string;
}

interface Window {
  // The IITC plugin namespace; IITC defines it before plugins boot, but the
  // wrapper also guards against it being absent.
  plugin?: (...args: unknown[]) => void;
  // Queue of setup callbacks IITC runs once its core has loaded.
  bootPlugins?: IITCSetup[];
  // True once IITC has finished booting; lets late-loading plugins self-start.
  iitcLoaded?: boolean;
  // Registers a layer in IITC's layer chooser (name, layer, default-on).
  addLayerGroup?: (name: string, layerGroup: unknown, defaultDisplay: boolean) => void;
  // IITC's styled modal dialog.
  dialog?: (options: IITCDialogOptions) => unknown;
}
