// Main-thread wrapper: spawns the sync worker, forwards progress, and resolves
// with the result (or rejects on error). Vite bundles the worker from the
// new URL(...) reference.

import type { FullSyncResult } from "./orchestrate";
import type { SyncProgress } from "./engine";
import type { WorkerRequest, WorkerResponse } from "./sync.worker";

export function runSyncInWorker(
  accessToken: string,
  onProgress?: (progress: SyncProgress) => void,
): Promise<FullSyncResult> {
  const worker = new Worker(new URL("./sync.worker.ts", import.meta.url), { type: "module" });

  return new Promise<FullSyncResult>((resolve, reject) => {
    worker.onmessage = (event: MessageEvent<WorkerResponse>) => {
      const message = event.data;
      if (message.type === "progress") {
        onProgress?.(message.progress);
      } else if (message.type === "done") {
        resolve(message.result);
        worker.terminate();
      } else {
        reject(new Error(message.message));
        worker.terminate();
      }
    };
    worker.onerror = (event) => {
      reject(new Error(event.message || "sync worker error"));
      worker.terminate();
    };
    worker.postMessage({ accessToken } satisfies WorkerRequest);
  });
}
