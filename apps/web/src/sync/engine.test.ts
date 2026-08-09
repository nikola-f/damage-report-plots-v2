import { describe, it, expect, vi } from "vitest";
import { runSync, type FetchLike, type SyncProgress } from "./engine";
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

  it("splits into 20-id batches and pauses between them (concurrency guard)", async () => {
    const sleep = vi.fn(async () => {});
    const ids = Array.from({ length: 21 }, (_, i) => `t${i}`);
    const mkThreads = (chunk: string[], base: number) =>
      chunk.map((id, i) => thread(id, base + i + 1, html(`P${base + i}`, `${base + i}.0,1.0`, "Me", "Me")));
    const fetchFn = router(
      [listResponse(ids)],
      [batchResponse(mkThreads(ids.slice(0, 20), 0)), batchResponse(mkThreads(ids.slice(20), 20))],
    );

    const { records } = await runSync({
      accessToken: "tok",
      fetchFn,
      since: T0,
      until: T0 + 5 * DAY,
      sleep,
    });

    expect(records).toHaveLength(21); // both batches processed
    expect(sleep).toHaveBeenCalledTimes(1); // exactly one pause between the two batches
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
});
