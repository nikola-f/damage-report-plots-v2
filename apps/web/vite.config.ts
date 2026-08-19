import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// No dev proxy: the SPA talks to Google's APIs directly from the browser, and
// the Rails backend the old /api and /auth proxies pointed at was decommissioned
// with the client-side migration (Phase 3).
export default defineConfig({
  plugins: [react()],
});
