// Backoff shared by every Google API call in the sync. It started inside
// engine.ts, wrapping only threads.list and the batched threads.get, which left
// the Sheets and Drive calls with no retry at all — a single transient 503 from
// spreadsheets.create aborted the whole sync, as one did on the first
// production run.
//
// Retry is applied per call site rather than to `fetch` as a whole, because
// only some of these requests may be repeated safely. See the notes in
// sheets.ts and drive.ts for which and why.

export interface RetryInfo {
  attempt: number; // 1-based
  maxRetries: number;
  waitMs: number;
  // Status plus Google's error.message — no request body, no user data (see
  // apiError). Safe to print.
  reason: string;
}

export interface RetryOptions {
  sleep?: (ms: number) => Promise<void>;
  maxRetries?: number;
  maxBackoff?: number; // seconds
  // Called before each backoff. Defaults to a console.warn so a rate-limited
  // run is visible while debugging; override to silence or collect.
  onRetry?: (info: RetryInfo) => void;
}

export const DEFAULT_MAX_RETRIES = 6; // 1+2+4+8+16+32 = 63s, covers one quota window
export const DEFAULT_MAX_BACKOFF = 32; // seconds

// Mirrors the Ruby GmailThreadBatchFetcher retry trigger. It matches on the
// message rather than the status because Gmail reports the per-user quota as a
// **403**, not a 429 ("Quota exceeded for quota metric 'Queries' …"), and a 403
// is otherwise a permission error that must not be retried — only the body
// tells them apart. See apiError.
export const RETRYABLE = /429|503|Rate Limit Exceeded|Quota exceeded|Too many concurrent|unavailable/i;

const warn = (info: RetryInfo) =>
  console.warn(
    `[sync] rate limited, backing off ${info.waitMs}ms ` +
      `(attempt ${info.attempt}/${info.maxRetries}): ${info.reason}`,
  );

// Build the error for a non-2xx Google response. Google's reason lives in the
// JSON body, not the status, so it is folded into the message for RETRYABLE to
// match on. Only `error.message` is used, never the raw body, which can carry
// user data (the retired GoogleApiClient#error_message did the same).
export async function apiError(res: Response, label: string): Promise<Error> {
  let detail: string | undefined;
  try {
    detail = (JSON.parse(await res.text()) as { error?: { message?: string } }).error?.message;
  } catch {
    // non-JSON body — the status alone has to carry the signal
  }
  return new Error([label, String(res.status), detail].filter(Boolean).join(" "));
}

// Retry `fn` with exponential backoff while its error looks rate-related.
//
// Each backoff is reported through onRetry. Without it a rate-limited run is
// invisible from the browser: a rejected batch sub-request rides inside a 200
// multipart response, so the network panel shows only the outer 200 and the
// retry looks like an ordinary duplicate request.
export async function withRetry<T>(
  fn: () => Promise<T>,
  opts: RetryOptions = {},
  attempt = 0,
): Promise<T> {
  const maxRetries = opts.maxRetries ?? DEFAULT_MAX_RETRIES;
  const maxBackoff = opts.maxBackoff ?? DEFAULT_MAX_BACKOFF;
  try {
    return await fn();
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (attempt < maxRetries && RETRYABLE.test(message)) {
      const waitMs = Math.min(2 ** attempt, maxBackoff) * 1000;
      (opts.onRetry ?? warn)({ attempt: attempt + 1, maxRetries, waitMs, reason: message });
      await (opts.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms))))(waitMs);
      return withRetry(fn, opts, attempt + 1);
    }
    throw e;
  }
}
