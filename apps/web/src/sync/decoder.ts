// Port of apps/api/lib/email_html_decoder.rb.
// Runs in the browser (jsdom in tests) using native DOMParser + document.evaluate
// — no Nokogiri, no server. Extracts attacked portals from a damage-report email.

import type { DamageReportRecord } from "./record";

const PORTAL_XPATH = "//tbody/tr/td[div/a[contains(@href,'ingress.com/intel')]]";

// Decode a Gmail base64url message-part body into a parsed HTML document.
export function decodeHtmlBody(base64url: string): Document {
  const b64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(b64);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  const html = new TextDecoder("utf-8").decode(bytes);
  return new DOMParser().parseFromString(html, "text/html");
}

function xString(doc: Document, ctx: Node, expr: string): string {
  return doc.evaluate(expr, ctx, null, XPathResult.STRING_TYPE, null).stringValue;
}

function xNodes(doc: Document, ctx: Node, expr: string): Node[] {
  const snapshot = doc.evaluate(expr, ctx, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  const out: Node[] = [];
  for (let i = 0; i < snapshot.snapshotLength; i++) out.push(snapshot.snapshotItem(i)!);
  return out;
}

function xFirst(doc: Document, ctx: Node, expr: string): Node | null {
  return doc.evaluate(expr, ctx, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
}

// internalDate is Gmail's epoch-ms string, carried onto each record unchanged.
export function extractPortals(doc: Document, internalDate: string): DamageReportRecord[] {
  const agentName = xString(
    doc,
    doc,
    "//span[contains(text(),'Agent Name:')]/following-sibling::span[1]",
  ).trim();

  return xNodes(doc, doc, PORTAL_XPATH).map((node) => {
    const ownerRaw = xString(doc, node, "string(../following-sibling::tr[contains(.,'Owner:')])");
    const owner = ownerRaw.includes("Owner: ")
      ? ownerRaw.split("Owner: ")[1].split(/[\n\r]/)[0].trim()
      : null;

    const anchor = xFirst(doc, node, "div[2]/a") as Element | null;
    const intelUrl = anchor?.getAttribute("href") ?? null;
    const pll = intelUrl?.match(/[?&]pll=([^&]+)/)?.[1] ?? null;
    const [lat, lng] = pll ? pll.split(",") : [null, null];

    return {
      name: xString(doc, node, "string(div[1])"),
      latitude: lat ?? "",
      longitude: lng ?? "",
      owned: Boolean(agentName && owner && agentName === owner),
      internalDate,
    };
  });
}
