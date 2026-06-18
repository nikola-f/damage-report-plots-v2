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

interface Window {
  // The IITC plugin namespace; IITC defines it before plugins boot, but the
  // wrapper also guards against it being absent.
  plugin?: (...args: unknown[]) => void;
  // Queue of setup callbacks IITC runs once its core has loaded.
  bootPlugins?: IITCSetup[];
  // True once IITC has finished booting; lets late-loading plugins self-start.
  iitcLoaded?: boolean;
}
