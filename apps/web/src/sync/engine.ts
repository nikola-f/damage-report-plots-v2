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

// Gmail meters each account against a per-user, per-project budget expressed in
// "quota units"; exceeding it fails requests with a 403 whose body reads
// "Quota exceeded for quota metric 'Queries'". This project is still on the
// pre-May-2026 quota set — the Cloud console reports its limit as
// "Previous quota: Units per minute per user" = 15,000, where threads.get costs
// 10 units. Projects on the post-May-2026 set instead get 6,000 units/min with
// threads.get at 40; if this app is ever pointed at such a project, these two
// numbers are what change. https://developers.google.com/workspace/gmail/api/reference/quota
//
// The 10 is corroborated by the console's usage graph: a day of syncing peaked
// at 18,000 units/min, which the 40-unit cost could not produce from the same
// traffic (it would be ~107,000). The pre-May-2026 cost table is not published,
// so the graph is the only check available.
export const QUOTA_UNITS_PER_MINUTE = 15_000;
export const THREADS_GET_UNITS = 10;
// Headroom for threads.list (10 units per page, and history scans sweep many
// empty windows in a burst) plus anything else using the same account.
const QUOTA_UTILISATION = 0.8;

// Each batched threads.get sub-request runs concurrently server-side, so the
// batch size is Gmail's per-user *concurrency* budget — a limit separate from
// the per-minute quota above, and one that pacing between batches cannot
// relieve. Exceeding it returns "Too many concurrent requests for user" 429s,
// which is what the console still reported at 40 (the retired server ran 20).
//
// Halving it costs nothing: MIN_BATCH_INTERVAL_MS is derived from BATCH_SIZE,
// so throughput is BATCH_SIZE / interval — identical either way (1,200
// threads/min). It only halves how many sub-requests fly at once, and how much
// work a 429 retry throws away, since a rejected part re-runs the whole batch.
export const BATCH_SIZE = 20;
// Minimum time between the *starts* of consecutive batches, derived from the
// budget rather than hand-tuned — a batch costs BATCH_SIZE × THREADS_GET_UNITS,
// so picking the size and the pause independently is how this app came to run
// over quota. engine.test.ts guards the arithmetic.
//
// Pacing on the interval, not on a fixed gap after each batch, because the
// request's own duration counts against the same window: threads.get for 40 ids
// measured ~400ms, so a fixed 500ms gap actually cycled every ~900ms — 1.8x the
// budget. Subtracting the elapsed time also stops a slow connection from being
// throttled twice over.
export const MIN_BATCH_INTERVAL_MS = Math.ceil(
  (BATCH_SIZE * THREADS_GET_UNITS * 60_000) / (QUOTA_UNITS_PER_MINUTE * QUOTA_UTILISATION),
);
const HTML_MIME = "text/html";
const DEFAULT_MAX_RETRIES = 6; // 1+2+4+8+16+32 = 63s, covers one quota window
const DEFAULT_MAX_BACKOFF = 32; // seconds
// Cap threads discovered per run so a first-time full-history scan is bounded
// (keeps a run inside the token lifetime); resume continues next sync. Based on
// the server's thread_list_worker_thread_id_limit (tuned down to 5000).
const DEFAULT_THREAD_LIMIT = 5000;

// Mirrors the Ruby GmailThreadBatchFetcher retry trigger. It matches on the
// message rather than the status because Gmail reports the per-user quota as a
// **403**, not a 429 ("Quota exceeded for quota metric 'Queries' …"), and a 403
// is otherwise a permission error that must not be retried — only the body
// tells them apart. See apiError.
const RETRYABLE = /429|503|Rate Limit Exceeded|Quota exceeded|Too many concurrent|unavailable/i;

export interface SyncProgress {
  phase: "list" | "fetch" | "done";
  windowStart: number; // epoch seconds of the window currently being scanned
  threadsFound: number;
  threadsProcessed: number;
  // Report rows persisted so far — the same quantity runFullSync returns as
  // `appended`, not a count of distinct portals (a portal accumulates many
  // reports, so the two differ by orders of magnitude).
  reportsFound: number;
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
  // Raw internalDate (ms) already persisted by a previous run. Gmail's after: is
  // day-granular, so `since` re-queries the whole last day; messages at or below
  // this mark were already written and are skipped instead of re-appended.
  sinceInternalDateMs?: number;
  until?: number; // upper bound epoch seconds; default now
  onProgress?: (p: SyncProgress) => void;
  // Called once per non-empty window with that window's deduped records and the
  // raw internalDate (ms) high-water mark of the messages behind them, so the
  // caller can persist progressively and advance the pointer in step. Throwing
  // aborts the run (earlier windows stay persisted).
  onWindow?: (records: DamageReportRecord[], maxInternalDate: number) => Promise<void>;
  // Called before each backoff. Defaults to a console.warn so a rate-limited
  // run is visible while debugging; override to silence or collect.
  onRetry?: (info: RetryInfo) => void;
  sleep?: (ms: number) => Promise<void>;
  clock?: () => number; // epoch ms, for batch pacing; injectable for tests
  maxRetries?: number;
  maxBackoff?: number; // seconds
  maxThreads?: number; // cap threads discovered per run; default DEFAULT_THREAD_LIMIT
}

export interface RetryInfo {
  attempt: number; // 1-based
  maxRetries: number;
  waitMs: number;
  // Status plus Google's error.message — no request body, no user data (see
  // apiError). Safe to print.
  reason: string;
}

interface RequestConfig {
  fetchFn: FetchLike;
  sleep: (ms: number) => Promise<void>;
  clock: () => number;
  maxRetries: number;
  maxBackoff: number;
  onRetry: (info: RetryInfo) => void;
}

// Build the error for a non-2xx Google response. Google's reason lives in the
// JSON body, not the status, so it is folded into the message for RETRYABLE to
// match on. Only `error.message` is used, never the raw body, which can carry
// user data (the retired GoogleApiClient#error_message did the same).
async function apiError(res: Response, label: string): Promise<Error> {
  let detail: string | undefined;
  try {
    detail = (JSON.parse(await res.text()) as { error?: { message?: string } }).error?.message;
  } catch {
    // non-JSON body — the status alone has to carry the signal
  }
  return new Error([label, String(res.status), detail].filter(Boolean).join(" "));
}

// Retry `fn` with exponential backoff while its error looks rate-related.
// Shared by threads.list and threads.get: both draw on the same per-user quota,
// so either can be the one that trips it.
//
// Each backoff is reported through cfg.onRetry. Without it a rate-limited run
// is invisible from the browser: a rejected batch sub-request rides inside a
// 200 multipart response, so the network panel shows only the outer 200 and
// the retry looks like an ordinary duplicate request.
async function withRetry<T>(cfg: RequestConfig, fn: () => Promise<T>, attempt = 0): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (attempt < cfg.maxRetries && RETRYABLE.test(message)) {
      const waitMs = Math.min(2 ** attempt, cfg.maxBackoff) * 1000;
      cfg.onRetry({ attempt: attempt + 1, maxRetries: cfg.maxRetries, waitMs, reason: message });
      await cfg.sleep(waitMs);
      return withRetry(cfg, fn, attempt + 1);
    }
    throw e;
  }
}

// `onPage` fires after every threads.list page so the discovered-thread count
// climbs as pagination proceeds instead of jumping once the window is fully
// listed.
async function listThreadIds(
  token: string,
  query: string,
  cfg: RequestConfig,
  onPage?: (added: number) => void,
): Promise<string[]> {
  const ids: string[] = [];
  let pageToken: string | undefined;
  do {
    const url = new URL(`${GMAIL_BASE}/users/me/threads`);
    url.searchParams.set("q", query);
    url.searchParams.set("fields", "threads/id,nextPageToken");
    if (pageToken) url.searchParams.set("pageToken", pageToken);

    const data = await withRetry(cfg, async () => {
      const res = await cfg.fetchFn(url.toString(), { headers: { Authorization: `Bearer ${token}` } });
      if (!res.ok) throw await apiError(res, "threads.list");
      // Gmail returns 204 No Content (empty body) when a window matches no
      // threads — common when scanning history — so there's nothing to parse.
      if (res.status === 204) return null;
      return (await res.json()) as { threads?: { id: string }[]; nextPageToken?: string };
    });
    if (!data) break;

    const page = data.threads ?? [];
    for (const t of page) ids.push(t.id);
    if (page.length > 0) onPage?.(page.length);
    pageToken = data.nextPageToken;
  } while (pageToken);
  return ids;
}

async function fetchBatch(token: string, chunk: string[], cfg: RequestConfig): Promise<GmailThread[]> {
  const res = await cfg.fetchFn(BATCH_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": `multipart/mixed; boundary=${BATCH_BOUNDARY}`,
    },
    body: buildBatchBody(chunk),
  });
  if (!res.ok) throw await apiError(res, "batch");
  const parsed = parseBatchResponse(await res.text(), res.headers.get("Content-Type") ?? "");
  return parsed.filter((t): t is GmailThread => t !== undefined);
}

// Rate limiter holding the start of consecutive batches at least `intervalMs`
// apart. Awaiting it yields only the shortfall, so a batch that already took
// longer than the interval proceeds immediately.
//
// One pacer spans the whole run rather than one per window: windows are only
// separated by a threads.list call (~300ms measured), which is not enough to
// cover a batch on its own.
function createPacer(cfg: RequestConfig, intervalMs: number): () => Promise<void> {
  let nextAllowedAt = 0; // 0 lets the first batch of the run start immediately
  return async () => {
    const wait = nextAllowedAt - cfg.clock();
    if (wait > 0) await cfg.sleep(wait);
    nextAllowedAt = cfg.clock() + intervalMs;
  };
}

// `onBatch` fires after each threads.get batch resolves (with how many thread
// ids that batch covered) so the processed count advances every ~40 threads
// rather than once per 30-day window.
async function batchGetThreads(
  token: string,
  ids: string[],
  cfg: RequestConfig,
  pace: () => Promise<void>,
  onBatch?: (processed: number) => void,
): Promise<GmailThread[]> {
  const threads: GmailThread[] = [];
  for (let i = 0; i < ids.length; i += BATCH_SIZE) {
    await pace();
    const chunk = ids.slice(i, i + BATCH_SIZE);
    threads.push(...(await withRetry(cfg, () => fetchBatch(token, chunk, cfg))));
    onBatch?.(chunk.length);
  }
  return threads;
}

export async function runSync(options: SyncOptions): Promise<SyncResult> {
  const fetchFn = options.fetchFn ?? defaultFetch;
  const cfg: RequestConfig = {
    fetchFn,
    sleep: options.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms))),
    clock: options.clock ?? (() => Date.now()),
    maxRetries: options.maxRetries ?? DEFAULT_MAX_RETRIES,
    maxBackoff: options.maxBackoff ?? DEFAULT_MAX_BACKOFF,
    onRetry:
      options.onRetry ??
      ((info) =>
        console.warn(
          `[sync] rate limited, backing off ${info.waitMs}ms ` +
            `(attempt ${info.attempt}/${info.maxRetries}): ${info.reason}`,
        )),
  };
  // threads.list is deliberately not paced: at 10 units a page it is what the
  // QUOTA_UTILISATION headroom covers, and holding it back would stall the
  // sweep across empty windows.
  const pace = createPacer(cfg, MIN_BATCH_INTERVAL_MS);
  const until = options.until ?? Math.floor(Date.now() / 1000);
  const maxThreads = options.maxThreads ?? DEFAULT_THREAD_LIMIT;
  let current = options.since ?? DEFAULT_AFTER_DATE;
  const sinceInternalDateMs = options.sinceInternalDateMs ?? 0;
  const alreadyPersisted = (internalDate: number) =>
    sinceInternalDateMs > 0 && internalDate > 0 && internalDate <= sinceInternalDateMs;

  const collected: DamageReportRecord[] = [];
  let maxInternalDate = 0;
  let threadsFound = 0;
  let threadsProcessed = 0;
  let truncated = false;

  // Single snapshot of the live counters, so every call site reports the same
  // numbers and each counter can be published the moment it changes:
  // threadsFound per threads.list page, threadsProcessed per threads.get batch,
  // reportsFound once the window's records are persisted by onWindow.
  const emit = (phase: SyncProgress["phase"], windowStart = current) =>
    options.onProgress?.({
      phase,
      windowStart,
      threadsFound,
      threadsProcessed,
      reportsFound: collected.length,
    });

  while (current < until) {
    const before = current + DAYS_WINDOW * SECONDS_PER_DAY;
    emit("list");

    const ids = await listThreadIds(
      options.accessToken,
      buildQuery(current, before),
      cfg,
      (added) => {
        threadsFound += added;
        emit("list");
      },
    );

    if (ids.length > 0) {
      const threads = await batchGetThreads(options.accessToken, ids, cfg, pace, (processed) => {
        threadsProcessed += processed;
        emit("fetch");
      });
      const windowRecords: DamageReportRecord[] = [];
      let windowMaxInternalDate = 0;
      for (const thread of threads) {
        for (const msg of thread.messages ?? []) {
          const internalDate = Number(msg.internalDate ?? 0);
          if (msg.internalDate) maxInternalDate = Math.max(maxInternalDate, internalDate);
          // Already written by an earlier run (the overlap day re-queried
          // because Gmail's after: is day-granular) — skip so it isn't appended
          // twice, which would inflate the plots `count`.
          if (alreadyPersisted(internalDate)) continue;
          windowMaxInternalDate = Math.max(windowMaxInternalDate, internalDate);
          const data = (msg.payload?.parts ?? []).find((p) => p.mimeType === HTML_MIME)?.body?.data;
          if (!data) continue;
          windowRecords.push(...extractPortals(decodeHtmlBody(data), msg.internalDate ?? "0"));
        }
      }

      // All reports for a given day are in this one 30-day window, so
      // window-scoped dedup fully collapses same-day/same-portal duplicates.
      const windowDeduped = deduplicate(windowRecords);
      if (windowDeduped.length > 0) await options.onWindow?.(windowDeduped, windowMaxInternalDate);
      collected.push(...windowDeduped);

      // Only now are these portals in the sheet, so this is where the count is
      // published.
      emit("fetch");
    }

    current = before;

    // Bound the run once enough threads are discovered (server parity). If more
    // history remains, flag truncation so the caller resumes on the next sync.
    if (threadsFound > maxThreads) {
      truncated = current < until;
      break;
    }
  }

  emit("done", until);
  return { records: collected, maxInternalDate, truncated };
}
