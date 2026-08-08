"use strict";

// CASA client-side PoC — R1/R2 検証スパイク（使い捨て）
//
// 目的: Gmail の取得・解析をブラウザ内のみで完結できるかを実測する。
//   R1: batch endpoint / 並列 GET が実認証リクエストで通るか（CORS + 動作）
//   R2: スループットからフル履歴スキャンの所要時間を推定
//   R3: Sheets 作成 + 書き込みがブラウザから通るか
//
// サーバは一切関与しない（GIS token model でトークンをブラウザ内取得）。

// ---- 定数（apps/api 側からの移植） ---------------------------------------

// DamageReportQuery（apps/api/app/models/damage_report_query.rb）
const SUBJECT = "Ingress Damage Report: Entities attacked by";
const FROM = [
  "ingress-support@google.com",
  "ingress-support@nianticlabs.com",
  "ingress-support@nianticspatial.com",
];
const LARGER = "5K";
const SMALLER = "100K";

// GmailClient#THREAD_FIELDS（apps/api/lib/gmail_client.rb:11）
const THREAD_FIELDS =
  "messages/id,messages/internalDate,messages/payload/parts/mimeType,messages/payload/parts/body/data";

// EmailHtmlDecoder（apps/api/lib/email_html_decoder.rb）
const PORTAL_XPATH = "//tbody/tr/td[div/a[contains(@href,'ingress.com/intel')]]";
const HTML_MIME_TYPE = "text/html";

const SCOPES = [
  "email",
  "profile",
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/spreadsheets",
].join(" ");

const GMAIL_BASE = "https://gmail.googleapis.com/gmail/v1";
const BATCH_URL = "https://www.googleapis.com/batch/gmail/v1";
const BATCH_BOUNDARY = "batch_boundary_gmail_v1";
const SHEETS_BASE = "https://sheets.googleapis.com/v4";

// ---- 状態 ---------------------------------------------------------------

let accessToken = null;
let threadIds = [];

// ---- UI ヘルパ ----------------------------------------------------------

const $ = (id) => document.getElementById(id);
function log(msg) {
  const el = $("log");
  el.textContent += `[${new Date().toLocaleTimeString()}] ${msg}\n`;
  el.scrollTop = el.scrollHeight;
  console.log(msg);
}
function metric(label, value) {
  const el = document.createElement("span");
  el.className = "metric";
  el.textContent = `${label}: ${value}`;
  $("metrics").appendChild(el);
}
function enable(...ids) { ids.forEach((id) => ($(id).disabled = false)); }

// ---- 1. 認可（GIS token model, PKCE, secret 不要） -----------------------

$("btnAuth").onclick = () => {
  const clientId = $("clientId").value.trim();
  if (!clientId) { alert("OAuth Client ID を入力してください"); return; }
  const tokenClient = google.accounts.oauth2.initTokenClient({
    client_id: clientId,
    scope: SCOPES,
    callback: (resp) => {
      if (resp.error) { log("認可失敗: " + resp.error); return; }
      accessToken = resp.access_token;
      log("認可成功。access_token 取得（有効期限 " + resp.expires_in + "s, サーバ非経由）");
      enable("btnList", "btnSheet");
    },
  });
  tokenClient.requestAccessToken();
};

// ---- クエリ生成（DamageReportQuery#to_s の移植） -------------------------

function buildQuery(afterEpoch, beforeEpoch) {
  const fromPart = "{" + FROM.map((f) => `from:${f}`).join(" ") + "}";
  return `subject:${SUBJECT} after:${afterEpoch} before:${beforeEpoch} ${fromPart} larger:${LARGER} smaller:${SMALLER}`;
}

// ---- 2. threads.list（ページング） --------------------------------------

async function listThreads(q) {
  const ids = [];
  let pageToken = null;
  do {
    const url = new URL(`${GMAIL_BASE}/users/me/threads`);
    url.searchParams.set("q", q);
    url.searchParams.set("fields", "threads/id,nextPageToken");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
    if (!res.ok) throw new Error(`threads.list ${res.status}: ${await res.text()}`);
    const data = await res.json();
    (data.threads || []).forEach((t) => ids.push(t.id));
    pageToken = data.nextPageToken || null;
  } while (pageToken);
  return ids;
}

$("btnList").onclick = async () => {
  try {
    const days = Number($("windowDays").value);
    const now = Math.floor(Date.now() / 1000);
    const after = now - days * 86400;
    const q = buildQuery(after, now);
    log(`threads.list 実行: 過去 ${days} 日 / q=${q}`);
    const t0 = performance.now();
    threadIds = await listThreads(q);
    const ms = Math.round(performance.now() - t0);
    log(`threads.list 完了: ${threadIds.length} 件 / ${ms}ms`);
    metric("list threads", threadIds.length);
    metric("list time", ms + "ms");
    if (threadIds.length > 0) enable("btnBatch", "btnParallel");
    else log("該当スレッド 0 件。窓を広げるか、対象メールのあるアカウントで試してください。");
  } catch (e) { log("エラー: " + e.message); }
};

// ---- HTML 解析（EmailHtmlDecoder の移植, DOMParser + XPath） -------------

function base64UrlDecode(data) {
  const b64 = data.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64);
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  return new TextDecoder("utf-8").decode(bytes);
}

// raw thread messages(JSON) → 抽出ポータル配列
function extractFromThread(thread) {
  const out = [];
  for (const m of thread.messages || []) {
    const parts = m.payload?.parts || [];
    const htmlPart = parts.find((p) => p.mimeType === HTML_MIME_TYPE);
    const data = htmlPart?.body?.data;
    if (!data) continue;
    const html = base64UrlDecode(data);
    const doc = new DOMParser().parseFromString(html, "text/html");
    out.push(...extractPortals(doc, m.internalDate));
  }
  return out;
}

function xpathString(doc, contextNode, expr) {
  const r = doc.evaluate(expr, contextNode, null, XPathResult.STRING_TYPE, null);
  return r.stringValue;
}
function xpathNodes(doc, contextNode, expr) {
  const r = doc.evaluate(expr, contextNode, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  const nodes = [];
  for (let i = 0; i < r.snapshotLength; i++) nodes.push(r.snapshotItem(i));
  return nodes;
}
function xpathFirst(doc, contextNode, expr) {
  const r = doc.evaluate(expr, contextNode, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
  return r.singleNodeValue;
}

function extractPortals(doc, internalDate) {
  const agentName = xpathString(
    doc, doc, "//span[contains(text(),'Agent Name:')]/following-sibling::span[1]"
  ).trim();

  return xpathNodes(doc, doc, PORTAL_XPATH).map((node) => {
    const ownerRaw = xpathString(
      doc, node, "string(../following-sibling::tr[contains(.,'Owner:')])"
    );
    const owner = ownerRaw.includes("Owner: ")
      ? ownerRaw.split("Owner: ")[1].split(/[\n\r]/)[0].trim()
      : null;
    const aNode = xpathFirst(doc, node, "div[2]/a");
    const intelUrl = aNode ? aNode.getAttribute("href") : null;
    const pll = intelUrl && intelUrl.match(/[?&]pll=([^&]+)/)?.[1];
    const [lat, lng] = pll ? pll.split(",") : [null, null];
    const name = xpathString(doc, node, "string(div[1])");
    return { name, lat, lng, owned: agentName && owner ? agentName === owner : false, internalDate };
  });
}

// ---- 3a. R1: BATCH 取得 -------------------------------------------------

async function batchGetThreads(ids) {
  let body = "";
  ids.forEach((id, i) => {
    body +=
      `--${BATCH_BOUNDARY}\r\n` +
      "Content-Type: application/http\r\n" +
      `Content-ID: <${i}>\r\n\r\n` +
      `GET /gmail/v1/users/me/threads/${encodeURIComponent(id)}?fields=${THREAD_FIELDS}\r\n\r\n`;
  });
  body += `--${BATCH_BOUNDARY}--\r\n`;

  const res = await fetch(BATCH_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": `multipart/mixed; boundary=${BATCH_BOUNDARY}`,
    },
    body,
  });
  if (!res.ok) throw new Error(`batch ${res.status}: ${await res.text()}`);
  return parseBatchResponse(await res.text(), res.headers.get("Content-Type"));
}

function parseBatchResponse(text, contentType) {
  const boundary = contentType.match(/boundary=([^\s;]+)/)[1];
  const parts = text.split(`--${boundary}`).slice(1, -1);
  const threads = [];
  for (const part of parts) {
    const [, httpResponse] = part.split(/\r?\n\r?\n/, 2).length >= 2
      ? [null, part.replace(/^[\s\S]*?\r?\n\r?\n/, "")]
      : [null, ""];
    const jsonStart = httpResponse.indexOf("{");
    if (jsonStart === -1) continue;
    try { threads.push(JSON.parse(httpResponse.slice(jsonStart))); } catch (_) {}
  }
  return threads;
}

$("btnBatch").onclick = async () => {
  try {
    log(`R1 BATCH 検証: ${threadIds.length} 件を 100 件/リクエストで取得`);
    const t0 = performance.now();
    let portals = 0;
    for (let i = 0; i < threadIds.length; i += 100) {
      const chunk = threadIds.slice(i, i + 100);
      const threads = await batchGetThreads(chunk);
      threads.forEach((t) => (portals += extractFromThread(t).length));
      log(`  batch ${i / 100 + 1}: ${threads.length} threads`);
    }
    const ms = Math.round(performance.now() - t0);
    const tps = (threadIds.length / (ms / 1000)).toFixed(1);
    log(`R1 BATCH 完了 ✅ 抽出ポータル ${portals} 件 / ${ms}ms / ${tps} threads/s`);
    metric("BATCH tps", tps);
    reportFullScanEstimate(tps);
  } catch (e) { log("R1 BATCH エラー ❌: " + e.message + "（CORS 失敗ならここに出る）"); }
};

// ---- 3b. R1: 並列 GET 取得（batch フォールバック） ----------------------

async function getThread(id) {
  const url = `${GMAIL_BASE}/users/me/threads/${encodeURIComponent(id)}?fields=${THREAD_FIELDS}`;
  let attempt = 0;
  for (;;) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
    if (res.ok) return res.json();
    if ((res.status === 429 || res.status === 503) && attempt < 6) {
      await new Promise((r) => setTimeout(r, Math.min(2 ** attempt, 32) * 1000));
      attempt++;
      continue;
    }
    throw new Error(`threads.get ${res.status}`);
  }
}

async function runPool(ids, concurrency, worker) {
  let idx = 0;
  const runNext = async () => {
    while (idx < ids.length) {
      const i = idx++;
      await worker(ids[i]);
    }
  };
  await Promise.all(Array.from({ length: concurrency }, runNext));
}

$("btnParallel").onclick = async () => {
  try {
    const concurrency = Number($("concurrency").value);
    log(`R1 並列 GET 検証: ${threadIds.length} 件 / 同時 ${concurrency}`);
    const t0 = performance.now();
    let portals = 0, done = 0;
    await runPool(threadIds, concurrency, async (id) => {
      const thread = await getThread(id);
      portals += extractFromThread(thread).length;
      if (++done % 50 === 0) log(`  ${done}/${threadIds.length}`);
    });
    const ms = Math.round(performance.now() - t0);
    const tps = (threadIds.length / (ms / 1000)).toFixed(1);
    log(`R1 並列 GET 完了 ✅ 抽出ポータル ${portals} 件 / ${ms}ms / ${tps} threads/s`);
    metric("parallelGET tps", tps);
    reportFullScanEstimate(tps);
  } catch (e) { log("R1 並列 GET エラー ❌: " + e.message); }
};

// ---- R2: フルスキャン推定 ----------------------------------------------

function reportFullScanEstimate(tps) {
  const FULL = 6000; // thread_list_worker_thread_id_limit
  const sec = FULL / Number(tps);
  const min = (sec / 60).toFixed(1);
  const withinToken = sec < 3600;
  log(`R2 推定: フル ${FULL} 件 ≈ ${min} 分 / トークン寿命(1h)内=${withinToken ? "はい ✅" : "いいえ ⚠ 分割 resume 必須"}`);
  metric("full-scan 推定", `${min}min`);
}

// ---- 4. R3: Sheets 作成 + 書き込み --------------------------------------

$("btnSheet").onclick = async () => {
  try {
    log("R3 Sheets 検証: spreadsheets.create");
    const createRes = await fetch(`${SHEETS_BASE}/spreadsheets`, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ properties: { title: `CASA PoC ${new Date().toISOString()}` } }),
    });
    if (!createRes.ok) throw new Error(`create ${createRes.status}: ${await createRes.text()}`);
    const { spreadsheetId } = await createRes.json();
    log(`  作成成功: ${spreadsheetId}`);

    const appendRes = await fetch(
      `${SHEETS_BASE}/spreadsheets/${spreadsheetId}/values/A1:append?valueInputOption=RAW`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ values: [["poc", 35.0, 139.0, 1]] }),
      }
    );
    if (!appendRes.ok) throw new Error(`append ${appendRes.status}: ${await appendRes.text()}`);
    log("R3 Sheets 完了 ✅ 作成+書込ともブラウザから成功（CASA 対象外の経路が成立）");
    metric("Sheets R3", "OK");
  } catch (e) { log("R3 Sheets エラー ❌: " + e.message); }
};
