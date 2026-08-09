import { describe, it, expect } from "vitest";
import { decodeHtmlBody, extractPortals } from "./decoder";

const SAMPLE_HTML = `
<table><tbody>
  <tr><td>
    <div>Alpha Portal</div>
    <div><a href="https://intel.ingress.com/intel?pll=35.1,139.2">map</a></div>
  </td></tr>
  <tr><td>Owner: AgentX</td></tr>
  <tr><td>
    <div>Beta Portal</div>
    <div><a href="https://intel.ingress.com/intel?pll=10.0,20.0">map</a></div>
  </td></tr>
  <tr><td>Owner: SomeoneElse</td></tr>
</tbody></table>
<span>Agent Name:</span><span>AgentX</span>
`;

function toBase64Url(s: string): string {
  // Sample HTML is ASCII, so btoa is sufficient (and keeps tests @types/node-free).
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_");
}

describe("extractPortals", () => {
  const doc = new DOMParser().parseFromString(SAMPLE_HTML, "text/html");
  const portals = extractPortals(doc, "1700000000000");

  it("extracts one record per attacked portal", () => {
    expect(portals).toHaveLength(2);
    expect(portals.map((p) => p.name)).toEqual(["Alpha Portal", "Beta Portal"]);
  });

  it("parses lat/lng from the intel pll parameter", () => {
    expect(portals[0]).toMatchObject({ latitude: "35.1", longitude: "139.2" });
    expect(portals[1]).toMatchObject({ latitude: "10.0", longitude: "20.0" });
  });

  it("marks owned:true only when the owner equals the agent name", () => {
    expect(portals[0].owned).toBe(true); // AgentX === AgentX
    expect(portals[1].owned).toBe(false); // SomeoneElse !== AgentX
  });

  it("day-truncates the internalDate into 100-second units", () => {
    // floor(1700000000000 / 86400000) * 864 = 19675 * 864
    expect(portals[0].internalDate).toBe(16_999_200);
  });
});

describe("decodeHtmlBody", () => {
  it("decodes a base64url body and yields a parseable document", () => {
    const doc = decodeHtmlBody(toBase64Url(SAMPLE_HTML));
    expect(extractPortals(doc, "0")).toHaveLength(2);
  });
});
