// Client-side sync engine. Collapses the server worker pipeline
// (GmailThreadListWorker → GmailThreadBatchFetcher/Worker) into one in-browser
// pass: windowed threads.list → batched threads.get → HTML extraction → dedupe.
// The Gmail access token and all message data stay in the browser.

import { DEFAULT_AFTER_DATE, DAYS_WINDOW, buildQuery } from "./query";
import {
  GMAIL_BASE,
  BATCH_URL,
  BATCH_BOUNDARY,
  buildBatchBody,
  parseBatchResponse,
  type GmailThread,
} from "./gmail";
import { decodeHtmlBody, extractPortals } from "./decoder";
import { deduplicate, type DamageReportRecord } from "./record";
import { defaultFetch, type FetchLike } from "./http";

export type { FetchLike };

const SECONDS_PER_DAY = 86_400;
// Each batched threads.get sub-request runs concurrently server-side, so the
// batch size is Gmail's per-user concurrency budget — not the API's 100 cap.
// Paired with a 1s inter-batch pause to stay under the "Too many concurrent
// requests for user" 429 limit (the server used 20; 40 is a tuned throughput
// bump — lower it again if concurrency 429s reappear).
const BATCH_SIZE = 40;
const INTER_BATCH_SLEEP_MS = 1000;
const HTML_MIME = "text/html";
const DEFAULT_MAX_RETRIES = 6; // 1+2+4+8+16+32 = 63s, covers one quota window
const DEFAULT_MAX_BACKOFF = 32; // seconds
// Cap threads discovered per run so a first-time full-history scan is bounded
// (keeps a run inside the token lifetime); resume continues next sync. Based on
// the server's thread_list_worker_thread_id_limit (tuned down to 5000).
const DEFAULT_THREAD_LIMIT = 5000;

// Mirrors the Ruby GmailThreadBatchFetcher retry trigger.
const RETRYABLE = /429|503|Rate Limit Exceeded|Quota exceeded|Too many concurrent|unavailable/i;

export interface SyncProgress {
  phase: "list" | "fetch" | "done";
  windowStart: number; // epoch seconds of the window currently being scanned
  threadsFound: number;
  threadsProcessed: number;
  portalsFound: number;
}

export interface SyncResult {
  records: DamageReportRecord[];
  // Raw Gmail internalDate (ms) high-water mark. The caller persists this and
  // passes it back as `since` (÷1000) to resume the next sync (Ruby parity).
  maxInternalDate: number;
  // True when the run stopped at the thread cap with history still unscanned —
  // the caller should prompt another sync to continue.
  truncated: boolean;
}

export interface SyncOptions {
  accessToken: string;
  fetchFn?: FetchLike;
  since?: number; // resume epoch seconds; default DEFAULT_AFTER_DATE
  until?: number; // upper bound epoch seconds; default now
  onProgress?: (p: SyncProgress) => void;
  sleep?: (ms: number) => Promise<void>;
  maxRetries?: number;
  maxBackoff?: number; // seconds
  maxThreads?: number; // cap threads discovered per run; default DEFAULT_THREAD_LIMIT
}

interface RetryConfig {
  fetchFn: FetchLike;
  sleep: (ms: number) => Promise<void>;
  maxRetries: number;
  maxBackoff: number;
}

async function listThreadIds(token: string, query: string, fetchFn: FetchLike): Promise<string[]> {
  const ids: string[] = [];
  let pageToken: string | undefined;
  do {
    const url = new URL(`${GMAIL_BASE}/users/me/threads`);
    url.searchParams.set("q", query);
    url.searchParams.set("fields", "threads/id,nextPageToken");
    if (pageToken) url.searchParams.set("pageToken", pageToken);

    const res = await fetchFn(url.toString(), { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`threads.list ${res.status}`);
    // Gmail returns 204 No Content (empty body) when a window matches no
    // threads — common when scanning history — so there's nothing to parse.
    if (res.status === 204) break;
    const data = (await res.json()) as { threads?: { id: string }[]; nextPageToken?: string };
    for (const t of data.threads ?? []) ids.push(t.id);
    pageToken = data.nextPageToken;
  } while (pageToken);
  return ids;
}

async function fetchBatchWithRetry(
  token: string,
  chunk: string[],
  cfg: RetryConfig,
  attempt = 0,
): Promise<GmailThread[]> {
  try {
    const res = await cfg.fetchFn(BATCH_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": `multipart/mixed; boundary=${BATCH_BOUNDARY}`,
      },
      body: buildBatchBody(chunk),
    });
    if (!res.ok) throw new Error(`batch ${res.status}`);
    const parsed = parseBatchResponse(await res.text(), res.headers.get("Content-Type") ?? "");
    return parsed.filter((t): t is GmailThread => t !== undefined);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (attempt < cfg.maxRetries && RETRYABLE.test(message)) {
      await cfg.sleep(Math.min(2 ** attempt, cfg.maxBackoff) * 1000);
      return fetchBatchWithRetry(token, chunk, cfg, attempt + 1);
    }
    throw e;
  }
}

async function batchGetThreads(token: string, ids: string[], cfg: RetryConfig): Promise<GmailThread[]> {
  const threads: GmailThread[] = [];
  for (let i = 0; i < ids.length; i += BATCH_SIZE) {
    if (i > 0) await cfg.sleep(INTER_BATCH_SLEEP_MS); // pace batches to stay under the concurrency limit
    threads.push(...(await fetchBatchWithRetry(token, ids.slice(i, i + BATCH_SIZE), cfg)));
  }
  return threads;
}

export async function runSync(options: SyncOptions): Promise<SyncResult> {
  const fetchFn = options.fetchFn ?? defaultFetch;
  const cfg: RetryConfig = {
    fetchFn,
    sleep: options.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms))),
    maxRetries: options.maxRetries ?? DEFAULT_MAX_RETRIES,
    maxBackoff: options.maxBackoff ?? DEFAULT_MAX_BACKOFF,
  };
  const until = options.until ?? Math.floor(Date.now() / 1000);
  const maxThreads = options.maxThreads ?? DEFAULT_THREAD_LIMIT;
  let current = options.since ?? DEFAULT_AFTER_DATE;

  const collected: DamageReportRecord[] = [];
  let maxInternalDate = 0;
  let threadsFound = 0;
  let threadsProcessed = 0;
  let truncated = false;

  while (current < until) {
    const before = current + DAYS_WINDOW * SECONDS_PER_DAY;
    options.onProgress?.({
      phase: "list",
      windowStart: current,
      threadsFound,
      threadsProcessed,
      portalsFound: collected.length,
    });

    const ids = await listThreadIds(options.accessToken, buildQuery(current, before), fetchFn);
    threadsFound += ids.length;

    if (ids.length > 0) {
      const threads = await batchGetThreads(options.accessToken, ids, cfg);
      for (const thread of threads) {
        for (const msg of thread.messages ?? []) {
          if (msg.internalDate) maxInternalDate = Math.max(maxInternalDate, Number(msg.internalDate));
          const data = (msg.payload?.parts ?? []).find((p) => p.mimeType === HTML_MIME)?.body?.data;
          if (!data) continue;
          collected.push(...extractPortals(decodeHtmlBody(data), msg.internalDate ?? "0"));
        }
      }
      threadsProcessed += ids.length;
      options.onProgress?.({
        phase: "fetch",
        windowStart: current,
        threadsFound,
        threadsProcessed,
        portalsFound: collected.length,
      });
    }

    current = before;

    // Bound the run once enough threads are discovered (server parity). If more
    // history remains, flag truncation so the caller resumes on the next sync.
    if (threadsFound > maxThreads) {
      truncated = current < until;
      break;
    }
  }

  const records = deduplicate(collected);
  options.onProgress?.({
    phase: "done",
    windowStart: until,
    threadsFound,
    threadsProcessed,
    portalsFound: records.length,
  });
  return { records, maxInternalDate, truncated };
}
