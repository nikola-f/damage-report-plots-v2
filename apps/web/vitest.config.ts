import { defineConfig } from "vitest/config";

// Standalone from vite.config.ts: the sync ports are framework-free logic tested
// under jsdom (DOMParser + document.evaluate for the HTML decoder). No React
// plugin needed here.
export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.ts"],
  },
});
