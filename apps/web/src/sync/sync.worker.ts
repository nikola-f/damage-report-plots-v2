// Web Worker entry: runs the full client-side sync off the main thread so a long
// historical scan never blocks the UI. All work (and the access token) stays in
// the browser. Typed loosely to avoid pulling the webworker lib into the app's
// DOM typing.

import { runFullSync, type FullSyncResult } from "./orchestrate";
import type { SyncProgress } from "./engine";

export interface WorkerRequest {
  accessToken: string;
}
export type WorkerResponse =
  | { type: "progress"; progress: SyncProgress }
  | { type: "done"; result: FullSyncResult }
  | { type: "error"; message: string };

const ctx = self as unknown as {
  postMessage: (message: WorkerResponse) => void;
  onmessage: ((event: { data: WorkerRequest }) => void) | null;
};

ctx.onmessage = async (event) => {
  try {
    const result = await runFullSync({
      accessToken: event.data.accessToken,
      onProgress: (progress) => ctx.postMessage({ type: "progress", progress }),
    });
    ctx.postMessage({ type: "done", result });
  } catch (err) {
    ctx.postMessage({ type: "error", message: err instanceof Error ? err.message : String(err) });
  }
};
