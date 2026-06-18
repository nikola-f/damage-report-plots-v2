// Plugin body. esbuild bundles this into a string that build.mjs inlines inside
// the userscript `wrapper(plugin_info)` function, so `plugin_info` resolves via
// closure at runtime (declared ambient in iitc.d.ts).
//
// This is a hello-world scaffold: it registers a setup callback that adds a
// single link to the IITC toolbox to prove the plugin loaded. Real damage-report
// rendering will be built on top of this later.

const setup: IITCSetup = function () {
  const link = document.createElement("a");
  link.textContent = "Damage Report Plots";
  link.title = "Damage Report Plots IITC plugin";
  link.addEventListener("click", () => {
    window.alert("Damage Report Plots IITC plugin is loaded.");
  });

  const toolbox = document.getElementById("toolbox");
  if (toolbox) toolbox.appendChild(link);

  console.log("[damage-report-plots] plugin loaded", plugin_info?.script?.version);
};

setup.info = plugin_info;
if (!window.bootPlugins) window.bootPlugins = [];
window.bootPlugins.push(setup);
// If IITC has already finished booting (plugin loaded late), run immediately.
if (window.iitcLoaded) setup();
