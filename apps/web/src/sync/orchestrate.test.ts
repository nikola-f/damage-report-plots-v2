import { describe, it, expect, vi } from "vitest";
import { runFullSync, readPlots } from "./orchestrate";
import { BATCH_URL } from "./gmail";
import type { FetchLike } from "./http";

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } });
}

function b64url(s: string): string {
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_");
}

function portalHtml(): string {
  return (
    `<table><tbody>` +
    `<tr><td><div>Alpha</div><div><a href="https://intel.ingress.com/intel?pll=35.1,139.2">m</a></div></td></tr>` +
    `<tr><td>Owner: Me</td></tr>` +
    `</tbody></table><span>Agent Name:</span><span>Me</span>`
  );
}

function batchResponse(internalDateMs = 1_700_000_000_000): Response {
  const boundary = "batchX";
  const thread = {
    messages: [
      {
        id: "m1",
        internalDate: String(internalDateMs),
        payload: { parts: [{ mimeType: "text/html", body: { data: b64url(portalHtml()) } }] },
      },
    ],
  };
  const body =
    `--${boundary}\r\nContent-Type: application/http\r\nContent-ID: <response-0>\r\n\r\n` +
    `HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n${JSON.stringify(thread)}\r\n` +
    `--${boundary}--\r\n`;
  return new Response(body, {
    status: 200,
    headers: { "Content-Type": `multipart/mixed; boundary=${boundary}` },
  });
}

const SINCE_UNITS = 16_999_200; // lastReportTime value in 100-second units
const SINCE = SINCE_UNITS * 100; // epoch seconds
const UNTIL = SINCE + 5 * 86_400; // one 30-day window

const MESSAGE_MS = 1_700_000_000_000; // the batch response's only message

// `pointer` is the value the stats!A7 cell returns (undefined = a sheet created
// before the precise pointer existed).
function fakeSheets(pointer?: number) {
  const appendBodies: unknown[] = [];
  const pointerWrites: number[] = [];

  const fetchFn = vi.fn(async (input: string, init?: RequestInit) => {
    const url = String(input);
    if (url.startsWith(BATCH_URL)) return batchResponse();
    if (url.includes("/drive/v3/files")) return json({ files: [{ id: "SHEET" }] }); // existing sheet
    if (url.includes("gmail.googleapis.com")) return json({ threads: [{ id: "t1" }] });
    if (url.includes("/values/lastReportTime")) return json({ values: [[SINCE_UNITS]] });
    if (url.includes("/values/stats")) {
      if (init?.method === "PUT") {
        pointerWrites.push((JSON.parse(init.body as string) as { values: number[][] }).values[0][0]);
        return json({});
      }
      return json(pointer === undefined ? {} : { values: [[pointer]] });
    }
    if (url.includes(":append")) {
      appendBodies.push(JSON.parse(init?.body as string));
      return json({});
    }
    throw new Error(`unexpected ${init?.method ?? "GET"} ${url}`);
  });

  return { fetchFn, appendBodies, pointerWrites };
}

// Same sheet fake, but each threads.get batch returns a message with the next
// queued internalDate — so successive windows can be given out-of-order dates.
function fakeSheetsWithDates(dates: number[]) {
  const pointerWrites: number[] = [];
  let batch = 0;

  const fetchFn = vi.fn(async (input: string, init?: RequestInit) => {
    const url = String(input);
    if (url.startsWith(BATCH_URL)) return batchResponse(dates[batch++]);
    if (url.includes("/drive/v3/files")) return json({ files: [{ id: "SHEET" }] });
    if (url.includes("gmail.googleapis.com")) return json({ threads: [{ id: "t1" }] });
    if (url.includes("/values/lastReportTime")) return json({ values: [[SINCE_UNITS]] });
    if (url.includes("/values/stats")) {
      if (init?.method === "PUT") {
        pointerWrites.push((JSON.parse(init.body as string) as { values: number[][] }).values[0][0]);
        return json({});
      }
      return json({});
    }
    if (url.includes(":append")) return json({});
    throw new Error(`unexpected ${init?.method ?? "GET"} ${url}`);
  });

  return { fetchFn, pointerWrites };
}

function run(fetchFn: unknown) {
  return runFullSync({
    accessToken: "tok",
    fetchFn: fetchFn as FetchLike,
    until: UNTIL,
    now: new Date(Date.UTC(2024, 0, 1)),
  });
}

describe("runFullSync", () => {
  it("resolves the sheet, resumes, scans, appends, and returns plots", async () => {
    const { fetchFn, appendBodies } = fakeSheets();

    const result = await run(fetchFn);

    expect(result.spreadsheetId).toBe("SHEET");
    expect(result.appended).toBe(1);
    expect(result.truncated).toBe(false);
    expect(appendBodies).toHaveLength(1);
  });

  it("advances the precise pointer to the message high-water mark after appending", async () => {
    const { fetchFn, pointerWrites } = fakeSheets();

    await run(fetchFn);

    expect(pointerWrites).toEqual([MESSAGE_MS]);
  });

  it("skips messages already covered by the pointer instead of re-appending them", async () => {
    // The resume day is re-queried (Gmail's after: is day-granular), so the same
    // message comes back; it must not be written a second time.
    const { fetchFn, appendBodies, pointerWrites } = fakeSheets(MESSAGE_MS);

    const result = await run(fetchFn);

    expect(result.appended).toBe(0);
    expect(appendBodies).toEqual([]);
    expect(pointerWrites).toEqual([]);
  });

  it("never moves the pointer backwards when a later window carries older mail", async () => {
    // threads.get returns a thread's whole history regardless of the queried
    // window, so an early window can surface mail newer than a later window's.
    // Writing each window's max unconditionally used to rewind the pointer and
    // let the next sync re-append rows already in the sheet.
    const older = MESSAGE_MS - 30 * 86_400_000;
    const { fetchFn, pointerWrites } = fakeSheetsWithDates([MESSAGE_MS, older]);

    await runFullSync({
      accessToken: "tok",
      fetchFn: fetchFn as unknown as FetchLike,
      until: SINCE + 60 * 86_400, // two 30-day windows
      now: new Date(Date.UTC(2024, 0, 1)),
    });

    expect(pointerWrites).toEqual([MESSAGE_MS]); // second window writes nothing
  });

  it("still appends messages newer than the pointer within the same day", async () => {
    const { fetchFn, appendBodies } = fakeSheets(MESSAGE_MS - 1);

    const result = await run(fetchFn);

    expect(result.appended).toBe(1);
    expect(appendBodies).toHaveLength(1);
  });
});

describe("readPlots", () => {
  it("reads plots!A:F fresh and maps it to Plot objects", async () => {
    const fetchFn = vi.fn(async (url: string) => {
      expect(url).toContain("/values/plots");
      return json({ values: [[35.1, 139.2, 1, 3, 17_000_000, 16_990_000]] });
    });

    const plots = await readPlots("tok", "SHEET", fetchFn as unknown as FetchLike);
    expect(plots).toEqual([
      { lat: 35.1, lng: 139.2, owned: 1, count: 3, latest: 17_000_000, oldest: 16_990_000 },
    ]);
  });
});
