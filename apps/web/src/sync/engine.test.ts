import { describe, it, expect, vi } from "vitest";
import {
  runSync,
  BATCH_SIZE,
  MIN_BATCH_INTERVAL_MS,
  QUOTA_UNITS_PER_MINUTE,
  THREADS_GET_UNITS,
  type FetchLike,
  type SyncProgress,
} from "./engine";
import { BATCH_URL } from "./gmail";

// --- fixtures -------------------------------------------------------------

function html(portal: string, pll: string, agent: string, owner: string): string {
  return (
    `<table><tbody>` +
    `<tr><td><div>${portal}</div><div><a href="https://intel.ingress.com/intel?pll=${pll}">m</a></div></td></tr>` +
    `<tr><td>Owner: ${owner}</td></tr>` +
    `</tbody></table><span>Agent Name:</span><span>${agent}</span>`
  );
}

function b64url(s: string): string {
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_");
}

interface Thread {
  messages: { id: string; internalDate: string; payload: { parts: unknown[] } }[];
}

function thread(id: string, internalDateMs: number, body: string): Thread {
  return {
    messages: [
      {
        id,
        internalDate: String(internalDateMs),
        payload: { parts: [{ mimeType: "text/html", body: { data: b64url(body) } }] },
      },
    ],
  };
}

function listResponse(ids: string[], nextPageToken?: string): Response {
  return new Response(JSON.stringify({ threads: ids.map((id) => ({ id })), nextPageToken }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

function batchResponse(threads: Thread[]): Response {
  const boundary = "batchX";
  let out = "";
  threads.forEach((t, i) => {
    out +=
      `--${boundary}\r\nContent-Type: application/http\r\nContent-ID: <response-${i}>\r\n\r\n` +
      `HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n${JSON.stringify(t)}\r\n`;
  });
  out += `--${boundary}--\r\n`;
  return new Response(out, {
    status: 200,
    headers: { "Content-Type": `multipart/mixed; boundary=${boundary}` },
  });
}

// fetch router that dispenses queued list/batch responses in order.
function router(lists: Response[], batches: Response[]): FetchLike {
  let li = 0;
  let bi = 0;
  return (async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url.startsWith(BATCH_URL)) return batches[bi++];
    if (url.includes("/users/me/threads")) return lists[li++];
    throw new Error(`unexpected url: ${url}`);
  }) as FetchLike;
}

const DAY = 86_400;
const T0 = Date.UTC(2024, 0, 1) / 1000; // window start (epoch seconds)

// --- tests ----------------------------------------------------------------

describe("runSync", () => {
  it("extracts portals across a window and deduplicates same-day duplicates", async () => {
    const fetchFn = router(
      [listResponse(["a", "b", "c"])],
      [
        batchResponse([
          thread("a", 1_700_000_000_000, html("Alpha", "35.1,139.2", "Me", "Me")), // owned
          thread("b", 1_700_000_001_000, html("Beta", "10.0,20.0", "Me", "Other")), // not owned
          thread("c", 1_700_000_000_500, html("Alpha", "35.1,139.2", "Me", "Other")), // dup of a, same day
        ]),
      ],
    );

    const { records, maxInternalDate } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 5 * DAY, // single 30-day window
    });

    expect(records.map((r) => r.name).sort()).toEqual(["Alpha", "Beta"]);
    const alpha = records.find((r) => r.name === "Alpha")!;
    expect(alpha.owned).toBe(true); // owned:true survives the dedupe
    // resume high-water mark is the raw internalDate (ms), not the truncated form
    expect(maxInternalDate).toBe(1_700_000_001_000);
  });

  it("follows threads.list pagination within a window", async () => {
    const fetchFn = router(
      [listResponse(["a"], "page2"), listResponse(["b"])],
      [batchResponse([thread("a", 1, html("A", "1,2", "Me", "Me")), thread("b", 2, html("B", "3,4", "Me", "Me"))])],
    );

    const { records } = await runSync({ accessToken: "tok", fetchFn, since: T0, until: T0 + 5 * DAY });

    expect(records.map((r) => r.name).sort()).toEqual(["A", "B"]);
  });

  // Exactly two batches (BATCH_SIZE + 1 ids) driven by a fake clock that only
  // the fake sleep and `batchMs` advance, so the pacing maths is exact.
  function pacedRun(batchMs: number) {
    let t = 0;
    const sleep = vi.fn(async (ms: number) => {
      t += ms;
    });
    const ids = Array.from({ length: BATCH_SIZE + 1 }, (_, i) => `t${i}`);
    const mkThreads = (chunk: string[], base: number) =>
      chunk.map((id, i) => thread(id, base + i + 1, html(`P${base + i}`, `${base + i}.0,1.0`, "Me", "Me")));
    const responses = router(
      [listResponse(ids)],
      [
        batchResponse(mkThreads(ids.slice(0, BATCH_SIZE), 0)),
        batchResponse(mkThreads(ids.slice(BATCH_SIZE), BATCH_SIZE)),
      ],
    );
    const fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input).startsWith(BATCH_URL)) t += batchMs; // the request's own duration
      return responses(input, init);
    }) as FetchLike;

    return {
      sleep,
      result: runSync({
        accessToken: "tok",
        fetchFn,
        since: T0,
        until: T0 + 5 * DAY,
        sleep,
        clock: () => t,
      }),
    };
  }

  it("subtracts a batch's own duration from the pace interval", async () => {
    const batchMs = 400; // measured: a threads.get batch takes ~400ms
    const { sleep, result } = pacedRun(batchMs);

    const { records } = await result;

    expect(records).toHaveLength(BATCH_SIZE + 1); // both batches processed
    expect(sleep).toHaveBeenCalledTimes(1); // one pause, between the two batches
    expect(sleep).toHaveBeenCalledWith(MIN_BATCH_INTERVAL_MS - batchMs);
  });

  it("does not pause at all when the batch outran the interval by itself", async () => {
    const { sleep, result } = pacedRun(MIN_BATCH_INTERVAL_MS + 100);

    const { records } = await result;

    expect(records).toHaveLength(BATCH_SIZE + 1);
    expect(sleep).not.toHaveBeenCalled(); // already slower than the quota allows
  });

  it("paces threads.get inside the Gmail per-user quota budget", () => {
    // Guards the pair (BATCH_SIZE, MIN_BATCH_INTERVAL_MS): raising the batch
    // size or shortening the interval in isolation is exactly how this app came
    // to run over quota and get 403s back from Gmail.
    const unitsPerBatch = BATCH_SIZE * THREADS_GET_UNITS;
    const batchesPerMinute = 60_000 / MIN_BATCH_INTERVAL_MS;
    expect(unitsPerBatch * batchesPerMinute).toBeLessThanOrEqual(QUOTA_UNITS_PER_MINUTE);
  });

  it("retries the batch request on a 429 with backoff", async () => {
    const sleep = vi.fn(async () => {});
    const fetchFn = router(
      [listResponse(["a"])],
      [new Response("{}", { status: 429 }), batchResponse([thread("a", 5, html("A", "1,2", "Me", "Me"))])],
    );

    const { records } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 5 * DAY,
      sleep,
    });

    expect(records).toHaveLength(1);
    expect(sleep).toHaveBeenCalledOnce();
  });

  it("retries a 429 that is inside an otherwise-200 batch response", async () => {
    // A rate-limited sub-request rides inside a 200 multipart body, so the
    // browser's network panel shows the batch as a plain 200 — the status only
    // exists on the inner part, which is where parseBatchResponse reads it.
    const boundary = "batchX";
    const ok = thread("a", 5, html("A", "1,2", "Me", "Me"));
    const mixed = new Response(
      `--${boundary}\r\nContent-Type: application/http\r\nContent-ID: <response-0>\r\n\r\n` +
        `HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n${JSON.stringify(ok)}\r\n` +
        `--${boundary}\r\nContent-Type: application/http\r\nContent-ID: <response-1>\r\n\r\n` +
        `HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\n\r\n` +
        `${JSON.stringify({ error: { message: "Too many concurrent requests for user" } })}\r\n` +
        `--${boundary}--\r\n`,
      { status: 200, headers: { "Content-Type": `multipart/mixed; boundary=${boundary}` } },
    );
    const sleep = vi.fn(async () => {});
    const fetchFn = router([listResponse(["a", "b"])], [mixed, batchResponse([ok])]);

    const { records } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 5 * DAY,
      sleep,
    });

    expect(sleep).toHaveBeenCalledOnce(); // backed off rather than losing the thread
    expect(records).toHaveLength(1);
  });

  // Gmail returns the per-user quota as a 403, not a 429, so the status alone
  // cannot separate it from a permission error — only the body can.
  function errorResponse(status: number, message: string): Response {
    return new Response(JSON.stringify({ error: { code: status, message } }), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  }

  it("retries threads.list when the per-user quota comes back as a 403", async () => {
    const sleep = vi.fn(async () => {});
    const fetchFn = router(
      [
        errorResponse(
          403,
          "Quota exceeded for quota metric 'Queries' and limit 'Previous quota: Units per minute per user'",
        ),
        listResponse(["a"]),
      ],
      [batchResponse([thread("a", 5, html("A", "1,2", "Me", "Me"))])],
    );

    const { records } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 5 * DAY,
      sleep,
    });

    expect(records).toHaveLength(1); // the retried page went through
    expect(sleep).toHaveBeenCalledOnce();
  });

  it("does not retry a 403 that is a real permission error", async () => {
    const sleep = vi.fn(async () => {});
    const fetchFn = router(
      [errorResponse(403, "Request had insufficient authentication scopes.")],
      [],
    );

    await expect(
      runSync({ accessToken: "tok", fetchFn, since: T0, until: T0 + 5 * DAY, sleep }),
    ).rejects.toThrow(/insufficient authentication scopes/);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("emits each window's records via onWindow for progressive persistence", async () => {
    const perWindow: number[] = [];
    const fetchFn = router(
      [listResponse(["a"]), listResponse(["b"])], // two windows, one thread each
      [
        batchResponse([thread("a", 1, html("A", "1,2", "Me", "Me"))]),
        batchResponse([thread("b", 2, html("B", "3,4", "Me", "Me"))]),
      ],
    );

    const { records } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 60 * DAY, // spans two 30-day windows
      onWindow: async (recs) => {
        perWindow.push(recs.length);
      },
    });

    expect(perWindow).toEqual([1, 1]); // one emission per non-empty window
    expect(records.map((r) => r.name).sort()).toEqual(["A", "B"]);
  });

  it("caps the run at maxThreads and flags truncation when history remains", async () => {
    const fetchFn = router(
      [listResponse(["a", "b"]), listResponse(["c", "d"])], // two windows available
      [batchResponse([thread("a", 1, html("A", "1,2", "Me", "Me")), thread("b", 2, html("B", "3,4", "Me", "Me"))])],
    );

    const { records, truncated } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 60 * DAY, // spans two 30-day windows
      maxThreads: 1, // exceeded after the first window
    });

    expect(truncated).toBe(true);
    expect(records.map((r) => r.name).sort()).toEqual(["A", "B"]); // only the first window was fetched
  });

  it("does not flag truncation when the scan reaches the end within the cap", async () => {
    const fetchFn = router([listResponse([])], []);
    const { truncated } = await runSync({ accessToken: "tok", fetchFn, since: T0, until: T0 + 5 * DAY });
    expect(truncated).toBe(false);
  });

  it("treats a 204 No Content window as empty (Gmail's empty-result response)", async () => {
    const fetchFn = router([new Response(null, { status: 204 })], []); // no batch call expected
    const { records } = await runSync({ accessToken: "tok", fetchFn, since: T0, until: T0 + 5 * DAY });
    expect(records).toHaveLength(0);
  });

  it("reports progress phases and skips windows with no threads", async () => {
    const phases: SyncProgress["phase"][] = [];
    const fetchFn = router([listResponse([])], []); // empty window, no batch call

    const { records } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 5 * DAY,
      onProgress: (p) => phases.push(p.phase),
    });

    expect(records).toHaveLength(0);
    expect(phases).toContain("list");
    expect(phases).not.toContain("fetch"); // no threads → no fetch phase
    expect(phases[phases.length - 1]).toBe("done");
  });

  it("publishes each counter as soon as it advances", async () => {
    // BATCH_SIZE + 1 threads over two list pages → two threads.get batches.
    const ids = Array.from({ length: BATCH_SIZE + 1 }, (_, i) => `t${i}`);
    const last = ids[BATCH_SIZE];
    const fetchFn = router(
      [listResponse(ids.slice(0, BATCH_SIZE), "page2"), listResponse(ids.slice(BATCH_SIZE))],
      [
        batchResponse(
          ids.slice(0, BATCH_SIZE).map((id, i) => thread(id, 1_000 + i, html(id, `1,${i}`, "Me", "Me"))),
        ),
        batchResponse([thread(last, 2_000, html(last, "9,9", "Me", "Me"))]),
      ],
    );

    const seen: SyncProgress[] = [];
    await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 5 * DAY,
      sleep: async () => {},
      onWindow: async () => {},
      onProgress: (p) => seen.push({ ...p }),
    });

    const listed = seen.filter((p) => p.phase === "list");
    // one emission per list page
    expect(listed.map((p) => p.threadsFound)).toEqual([0, BATCH_SIZE, BATCH_SIZE + 1]);

    const fetched = seen.filter((p) => p.phase === "fetch");
    // one per batch, then the window wrap-up
    expect(fetched.map((p) => p.threadsProcessed)).toEqual([BATCH_SIZE, BATCH_SIZE + 1, BATCH_SIZE + 1]);
    // portals stay at 0 until onWindow has persisted the window's records
    expect(fetched.map((p) => p.portalsFound)).toEqual([0, 0, BATCH_SIZE + 1]);
  });
});
