import { useEffect, useState } from "react";
import {
  requestAccessToken,
  revokeAccessToken,
  missingScopes,
  LOGIN_SCOPE,
  SYNC_SCOPE,
  SHEET_SCOPE,
  PROMPT_IF_NEEDED,
} from "./sync/auth.ts";
import type { SyncProgress } from "./sync/engine.ts";
import { runFullSync, readPlots, findSpreadsheet, type FullSyncResult } from "./sync/orchestrate.ts";
import type { Plot } from "./sync/mapping.ts";
import { fetchProfile, type Profile } from "./profile.ts";
import { readStats, type SheetStats } from "./sync/status.ts";
import { loadLastSync, saveLastSync, type LastSync } from "./localState.ts";
// Pre-approved "Sign in with Google" asset (dark theme, Android+Web @4x,
// 720x160 shown at 180x40) from
// https://developers.google.com/identity/branding-guidelines — do not restyle.
import googleSignin from "./assets/google-signin-dark.png";
import HowItWorks from "./HowItWorks.tsx";

// Injected at build time (CI per environment; a local .env for dev). Sign-in is
// disabled if it's missing.
const CLIENT_ID =
  (import.meta.env as unknown as { VITE_GOOGLE_CLIENT_ID?: string }).VITE_GOOGLE_CLIENT_ID ?? "";
// Re-request the token when under a minute of its ~1h life remains. Enough for
// the one-shot calls behind sign-in and Copy.
const TOKEN_MARGIN_MS = 60_000;
// A sync is not a single call: it holds one token for the whole run, which the
// engine's 5,000-thread cap bounds at roughly five minutes. A token with a
// minute left therefore passes the check above and then dies mid-run — and a
// 401 is deliberately not retryable (it is otherwise a permission error), so
// the run stops. Already-appended windows survive and the next sync resumes,
// but the user sees a failure that need not have happened.
//
// Twenty minutes is several times the worst-case run. It is free to be this
// generous because a re-request is silent now (see PROMPT_IF_NEEDED); before
// that it would have meant an account chooser.
const SYNC_TOKEN_MARGIN_MS = 20 * 60_000;

type Phase = "idle" | "syncing" | "done" | "error";

interface Token {
  value: string;
  expiresAt: number; // epoch ms
  scope: string; // the scopes Google granted it, as returned by GIS
}

// One plot per line: compact but diff-friendly, matching the old copy format the
// IITC plugin already parses.
function plotsJson(plots: Plot[]): string {
  return plots.length === 0 ? "[]" : `[\n${plots.map((p) => JSON.stringify(p)).join(",\n")}\n]`;
}

function fmtDay(epochSec?: number): string | null {
  return epochSec ? new Date(epochSec * 1000).toLocaleDateString() : null;
}

function fmtWhen(ms: number): string {
  return new Date(ms).toLocaleString();
}

// The margin above makes a mid-run expiry unlikely, not impossible: a suspended
// laptop or a stalled connection can still outlast the token. Google's wording
// for that is "Invalid Credentials", which reads like the app is broken rather
// than like a session that ran out.
function syncErrorMessage(e: unknown): string {
  const message = e instanceof Error ? e.message : "";
  if (/\b401\b/.test(message)) {
    return "Your Google session expired during the sync. Sync again to continue from where it stopped.";
  }
  return message || "Sync failed.";
}

function fmtDuration(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

export default function App() {
  const [token, setToken] = useState<Token | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [authError, setAuthError] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [progress, setProgress] = useState<SyncProgress | null>(null);
  const [result, setResult] = useState<FullSyncResult | null>(null);
  // The user's spreadsheet id, from this session's sync or discovered on login.
  // Persistent in Drive, so Copy works after a re-login without re-syncing.
  const [spreadsheetId, setSpreadsheetId] = useState<string | null>(null);
  const [syncError, setSyncError] = useState("");
  const [copyMessage, setCopyMessage] = useState("");
  // Post-login state: shared summary read from the sheet, plus this device's
  // last-sync record from localStorage.
  const [stats, setStats] = useState<SheetStats | null>(null);
  const [lastSync, setLastSync] = useState<LastSync | null>(null);
  // Elapsed time since the current/last sync started. `syncStartedAt` is null
  // until the first sync of the session.
  const [syncStartedAt, setSyncStartedAt] = useState<number | null>(null);
  const [elapsedMs, setElapsedMs] = useState(0);

  // Tick the elapsed clock once a second while a sync is running.
  useEffect(() => {
    if (phase !== "syncing" || syncStartedAt == null) return;
    const id = setInterval(() => setElapsedMs(Date.now() - syncStartedAt), 1000);
    return () => clearInterval(id);
  }, [phase, syncStartedAt]);

  // Load the cross-device summary (sheet) and this device's last-sync record.
  // Used on login, when the sheet's aggregates are settled.
  async function loadStatus(accessToken: string, id: string) {
    setLastSync(loadLastSync(id));
    try {
      setStats(await readStats(accessToken, id));
    } catch {
      // Never block the UI on the summary read; the sheet may be brand new.
    }
  }

  // After a sync the `plots` QUERY (and thus the stats COUNT) recalculates;
  // reading too soon returns 0. When we expect data, poll until the count
  // catches up so the card never flashes "0 portals". Falls through quietly if
  // it never settles — the previous summary stays on screen.
  async function refreshStatsAfterSync(accessToken: string, id: string, expectData: boolean) {
    for (let attempt = 0; attempt < 6; attempt++) {
      try {
        const s = await readStats(accessToken, id);
        if (!expectData || s.portals > 0) {
          setStats(s);
          return;
        }
      } catch {
        // keep retrying
      }
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
  }

  // Reuse the in-memory token while it is comfortably valid and already covers
  // what the caller needs; otherwise ask GIS for a fresh one.
  //
  // Coverage, not equality. There is one token slot, so a sync (Gmail + Drive)
  // replaces the login token (profile + Drive) — and an equality check then
  // treated the sync token as useless for reading the sheet, sending Copy back
  // to GIS for a third token and an account chooser on every click. Both tokens
  // carry drive.file, which is all Copy asks for.
  // `marginMs` is how much life the caller needs left on the token, which is a
  // property of the work it is about to do rather than of the token.
  async function acquireToken(
    scope: string,
    opts: { prompt?: string; marginMs?: number } = {},
  ): Promise<string> {
    if (
      token &&
      token.expiresAt - Date.now() > (opts.marginMs ?? TOKEN_MARGIN_MS) &&
      missingScopes(scope, token.scope).length === 0
    ) {
      return token.value;
    }
    const r = await requestAccessToken(CLIENT_ID, { scope, prompt: opts.prompt });
    setToken({
      value: r.accessToken,
      expiresAt: Date.now() + r.expiresIn * 1000,
      // What Google granted, which requestAccessToken has already checked covers
      // `scope`. Storing the grant rather than the request lets a wider token
      // satisfy a narrower need.
      scope: r.scope || scope,
    });
    return r.accessToken;
  }

  async function handleLogin() {
    setAuthError("");
    try {
      // Login asks only for identity + Drive; gmail.readonly is deferred to sync.
      const accessToken = await acquireToken(LOGIN_SCOPE);
      setProfile(await fetchProfile(accessToken));
      // Best-effort: find an existing spreadsheet so Copy is usable without a
      // fresh sync, and surface the last-sync summary. Never blocks login.
      findSpreadsheet(accessToken)
        .then((id) => {
          setSpreadsheetId(id);
          if (id) void loadStatus(accessToken, id);
        })
        .catch(() => {});
    } catch (e) {
      setAuthError(e instanceof Error ? e.message : "Sign-in failed.");
    }
  }

  function handleLogout() {
    // Hand the token back to Google before dropping it, so signing out actually
    // ends the grant instead of only hiding it (see revokeAccessToken). Fired
    // and forgotten: the UI signs out either way, and there is nothing useful
    // to tell the user if Google refuses.
    if (token) void revokeAccessToken(token.value).catch(() => {});
    setToken(null);
    setProfile(null);
    setResult(null);
    setSpreadsheetId(null);
    setProgress(null);
    setPhase("idle");
    setCopyMessage("");
    setStats(null);
    setLastSync(null);
  }

  async function handleSync() {
    const startedAt = Date.now();
    setSyncStartedAt(startedAt);
    setElapsedMs(0);
    setPhase("syncing");
    setSyncError("");
    setProgress(null);
    setCopyMessage("");
    try {
      // Sync needs gmail.readonly (read mail) + drive.file (write the sheet);
      // this is where the user is first prompted for Gmail access. Later syncs
      // reuse the grant without re-prompting.
      const accessToken = await acquireToken(SYNC_SCOPE, {
        prompt: PROMPT_IF_NEEDED,
        marginMs: SYNC_TOKEN_MARGIN_MS,
      });
      // Runs on the main thread: the HTML decoder needs DOMParser/document.evaluate,
      // which don't exist in a Web Worker. Work is network-bound and awaits between
      // batches, so progress renders and the UI stays responsive.
      const res = await runFullSync({ accessToken, onProgress: setProgress });
      setResult(res);
      setSpreadsheetId(res.spreadsheetId);
      setElapsedMs(Date.now() - startedAt);
      setPhase("done");
      // Record this device's sync and refresh the summary from the sheet. The
      // stats read is polled because the sheet's QUERY recalculates after the
      // append (see refreshStatsAfterSync).
      const record = { at: Date.now(), appended: res.appended };
      saveLastSync(res.spreadsheetId, record);
      setLastSync(record);
      const expectData = res.appended > 0 || (stats?.portals ?? 0) > 0;
      void refreshStatsAfterSync(accessToken, res.spreadsheetId, expectData);
    } catch (e) {
      setElapsedMs(Date.now() - startedAt);
      setSyncError(syncErrorMessage(e));
      setPhase("error");
    }
  }

  async function handleCopy() {
    if (!spreadsheetId) return;
    setCopyMessage("Reading plots…");
    try {
      // Reading the sheet needs only drive.file, which both the login and the
      // sync token carry — so Copy reuses whichever is in hand and never
      // triggers a prompt of its own.
      const accessToken = await acquireToken(SHEET_SCOPE, { prompt: PROMPT_IF_NEEDED });
      const plots = await readPlots(accessToken, spreadsheetId);
      await navigator.clipboard.writeText(plotsJson(plots));
      setCopyMessage(`Copied ${plots.length.toLocaleString()} plots to clipboard.`);
    } catch (e) {
      setCopyMessage(e instanceof Error ? e.message : "Copy failed.");
    }
  }

  if (!profile) {
    return (
      <div className="container">
        <h1 className="title">Damage Report Plots</h1>
        <HowItWorks />
        <button onClick={handleLogin} className="google-signin" disabled={!CLIENT_ID}>
          <img src={googleSignin} alt="Sign in with Google" height={40} />
        </button>
        {authError && <p className="message error">{authError}</p>}
        <footer className="footer">
          <a href="/about.html">How it works</a>
          <a href="/privacy.html">Privacy Policy</a>
        </footer>
      </div>
    );
  }

  const syncing = phase === "syncing";
  return (
    <div className="container">
      <header className="header">
        <h1 className="title">Damage Report Plots</h1>
        <div className="header-user">
          {profile.picture && <img src={profile.picture} alt={profile.name} className="avatar" />}
          <span className="name">{profile.name}</span>
          <button onClick={handleLogout} className="btn secondary">
            Logout
          </button>
        </div>
      </header>

      {(stats || lastSync) && (
        <div className="summary-card">
          {stats && stats.portals > 0 && (
            <div className="summary-row">
              <span className="summary-value">{stats.portals.toLocaleString()}</span>
              <span className="summary-label">
                portals tracked
                {stats.ownedPortals > 0 && ` - ${stats.ownedPortals.toLocaleString()} captured`}
              </span>
            </div>
          )}
          {stats && fmtDay(stats.latestReport) && (
            <div className="summary-row">
              <span className="summary-label">
                Reports {fmtDay(stats.oldestReport) ? `${fmtDay(stats.oldestReport)} – ` : "up to "}
                {fmtDay(stats.latestReport)}
              </span>
            </div>
          )}
          {lastSync && (
            <div className="summary-row">
              <span className="summary-label">
                Last synced on this device {fmtWhen(lastSync.at)}
                {lastSync.appended > 0 && ` - ${lastSync.appended.toLocaleString()} reports`}
              </span>
            </div>
          )}
        </div>
      )}

      <button onClick={handleSync} disabled={syncing} className="btn primary">
        {syncing ? `Syncing… Elapsed ${fmtDuration(elapsedMs)}` : "Sync Gmail → Sheet"}
      </button>

      {/* Fixed message slot so the layout doesn't jump. */}
      <p className={`message ${phase === "error" ? "error" : "success"}`}>
        {phase === "error"
          ? syncError
          : phase === "done"
            ? `Synced in ${fmtDuration(elapsedMs)}. ${result?.appended ?? 0} new report${result?.appended === 1 ? "" : "s"}.` +
              (result?.truncated ? " More reports remain — Sync again to continue." : "")
            : ""}
      </p>

      {/* Kept after completion (progress is cleared only when the next sync
          starts or on logout) so the final per-window state stays visible. */}
      {progress && (
        <div className="status-card">
          <p className="status-label">
            {progress.phase === "list" ? "Listing threads" : "Fetching threads"} - window{" "}
            {new Date(progress.windowStart * 1000).toLocaleDateString()}
          </p>
          <p className="status-label">
            threads {progress.threadsProcessed.toLocaleString()} /{" "}
            {progress.threadsFound.toLocaleString()} - reports{" "}
            {progress.reportsFound.toLocaleString()}
          </p>
        </div>
      )}

      <button onClick={handleCopy} disabled={!spreadsheetId} className="btn secondary">
        Copy plots JSON
      </button>
      <p className="message success">{copyMessage}</p>
    </div>
  );
}
