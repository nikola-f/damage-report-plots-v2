import { describe, it, expect, vi } from "vitest";
import { withRetry, apiError, RETRYABLE } from "./retry";
import { getValues } from "./sheets";
import type { FetchLike } from "./http";

const silent = { sleep: async () => {}, onRetry: () => {} };

describe("withRetry", () => {
  it("retries a rate-related failure and returns the eventual success", async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(new Error("spreadsheets.create 503"))
      .mockResolvedValue("ok");

    await expect(withRetry(fn, silent)).resolves.toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it("gives up after maxRetries and rethrows the last error", async () => {
    const fn = vi.fn().mockRejectedValue(new Error("503 unavailable"));
    await expect(withRetry(fn, { ...silent, maxRetries: 2 })).rejects.toThrow("503");
    expect(fn).toHaveBeenCalledTimes(3); // the first try plus two retries
  });

  it("does not retry an error that is not rate-related", async () => {
    const fn = vi.fn().mockRejectedValue(new Error("threads.list 403 Insufficient Permission"));
    await expect(withRetry(fn, silent)).rejects.toThrow("403");
    expect(fn).toHaveBeenCalledOnce();
  });

  // Gmail reports the per-user quota as a 403, so the status alone cannot decide
  // this — only the message separates it from a permission failure.
  it("retries a 403 that is really a quota error", async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(new Error("threads.list 403 Quota exceeded for quota metric 'Queries'"))
      .mockResolvedValue("ok");

    await expect(withRetry(fn, silent)).resolves.toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it("reports each backoff so a rate-limited run is not silent", async () => {
    const onRetry = vi.fn();
    const fn = vi.fn().mockRejectedValueOnce(new Error("429")).mockResolvedValue("ok");

    await withRetry(fn, { sleep: async () => {}, onRetry });
    expect(onRetry).toHaveBeenCalledWith(
      expect.objectContaining({ attempt: 1, waitMs: 1000, reason: "429" }),
    );
  });

  it("backs off exponentially up to the cap", async () => {
    const waits: number[] = [];
    const fn = vi.fn().mockRejectedValue(new Error("503"));
    await expect(
      withRetry(fn, {
        sleep: async (ms) => void waits.push(ms),
        onRetry: () => {},
        maxRetries: 5,
        maxBackoff: 4,
      }),
    ).rejects.toThrow();
    expect(waits).toEqual([1000, 2000, 4000, 4000, 4000]);
  });

  it("matches the statuses and phrases Google actually returns", () => {
    for (const m of ["429", "503", "Quota exceeded", "Too many concurrent requests for user"]) {
      expect(RETRYABLE.test(m)).toBe(true);
    }
    expect(RETRYABLE.test("400 Bad Request")).toBe(false);
  });
});

describe("apiError", () => {
  it("folds Google's message in so RETRYABLE can see it", async () => {
    const res = new Response(JSON.stringify({ error: { message: "Quota exceeded" } }), {
      status: 403,
    });
    const e = await apiError(res, "threads.list");
    expect(e.message).toBe("threads.list 403 Quota exceeded");
    expect(RETRYABLE.test(e.message)).toBe(true);
  });

  // The body can carry user data, so only error.message is ever read from it.
  it("keeps the rest of the body out of the message", async () => {
    const res = new Response(
      JSON.stringify({ error: { message: "boom", details: "user@example.com" } }),
      { status: 500 },
    );
    expect((await apiError(res, "x")).message).toBe("x 500 boom");
  });

  it("falls back to the status alone for a non-JSON body", async () => {
    expect((await apiError(new Response("<html>", { status: 502 }), "x")).message).toBe("x 502");
  });
});

// Wiring check: the Sheets read path actually consults withRetry now.
describe("sheets retry wiring", () => {
  it("retries values.get through a transient failure", async () => {
    const fetchFn = vi
      .fn()
      .mockResolvedValueOnce(new Response("", { status: 503 }))
      .mockResolvedValue(new Response(JSON.stringify({ values: [[1]] }), { status: 200 }));

    const rows = await getValues("tok", "SHEET", "plots!A:F", fetchFn as unknown as FetchLike, silent);
    expect(rows).toEqual([[1]]);
    expect(fetchFn).toHaveBeenCalledTimes(2);
  });
});
