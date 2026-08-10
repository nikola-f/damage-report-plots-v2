import { useEffect, useState } from "react";
import { requestAccessToken, LOGIN_SCOPE, SYNC_SCOPE } from "./sync/auth.ts";
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
// Re-request the token when under a minute of its ~1h life remains.
const TOKEN_MARGIN_MS = 60_000;

type Phase = "idle" | "syncing" | "done" | "error";

interface Token {
  value: string;
  expiresAt: number; // epoch ms
  scope: string; // the scope this token was requested for
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

  // Reuse the in-memory token while it is comfortably valid and was requested for
  // the same scope; otherwise ask GIS for a fresh one (silent when the Google
  // session is still active). Keying on scope keeps login (identity + Drive) and
  // sync (Gmail) tokens separate for incremental authorization.
  async function acquireToken(scope: string): Promise<string> {
    if (token && token.scope === scope && token.expiresAt - Date.now() > TOKEN_MARGIN_MS) {
      return token.value;
    }
    const r = await requestAccessToken(CLIENT_ID, { scope });
    setToken({ value: r.accessToken, expiresAt: Date.now() + r.expiresIn * 1000, scope });
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
      // this is where the user is first prompted for Gmail access.
      const accessToken = await acquireToken(SYNC_SCOPE);
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
      setSyncError(e instanceof Error ? e.message : "Sync failed.");
      setPhase("error");
    }
  }

  async function handleCopy() {
    if (!spreadsheetId) return;
    setCopyMessage("Reading plots…");
    try {
      // Reading the sheet needs only drive.file, so the login-scope token works
      // and Copy never triggers the Gmail prompt.
      const accessToken = await acquireToken(LOGIN_SCOPE);
      const plots = await readPlots(accessToken, spreadsheetId);
      await navigator.clipboard.writeText(plotsJson(plots));
      setCopyMessage(`Copied ${plots.length} plots to clipboard.`);
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
                {stats.ownedPortals > 0 && ` · ${stats.ownedPortals.toLocaleString()} owned`}
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
                {lastSync.appended > 0 && ` · +${lastSync.appended.toLocaleString()} reports`}
              </span>
            </div>
          )}
        </div>
      )}

      <button onClick={handleSync} disabled={syncing} className="btn primary">
        {syncing ? "Syncing…" : "Sync Gmail → Sheet"}
      </button>

      {/* Fixed message slot so the layout doesn't jump. */}
      <p className={`message ${phase === "error" ? "error" : "success"}`}>
        {phase === "error"
          ? syncError
          : phase === "done"
            ? `Synced in ${fmtDuration(elapsedMs)}. ${result?.appended ?? 0} new report${result?.appended === 1 ? "" : "s"}.` +
              (result?.truncated ? " More history remains — Sync again to continue." : "")
            : ""}
      </p>

      {syncing && (
        <div className="status-card">
          <p className="status-label">Elapsed {fmtDuration(elapsedMs)}</p>
          {progress && (
            <>
              <p className="status-label">
                {progress.phase === "list" ? "Listing threads" : "Fetching threads"} · window{" "}
                {new Date(progress.windowStart * 1000).toLocaleDateString()}
              </p>
              <p className="status-label">
                threads {progress.threadsProcessed} / {progress.threadsFound} · portals{" "}
                {progress.portalsFound}
              </p>
            </>
          )}
        </div>
      )}

      <button onClick={handleCopy} disabled={!spreadsheetId} className="btn secondary">
        Copy plots JSON
      </button>
      <p className="message success">{copyMessage}</p>
    </div>
  );
}
