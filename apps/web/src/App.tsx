import { useState } from "react";
import { requestAccessToken } from "./sync/auth.ts";
import type { SyncProgress } from "./sync/engine.ts";
import { runFullSync, type FullSyncResult } from "./sync/orchestrate.ts";
import type { Plot } from "./sync/mapping.ts";
import { fetchProfile, type Profile } from "./profile.ts";
// Pre-approved "Sign in with Google" asset (dark theme, Android+Web @4x,
// 720x160 shown at 180x40) from
// https://developers.google.com/identity/branding-guidelines — do not restyle.
import googleSignin from "./assets/google-signin-dark.png";
import HowItWorks from "./HowItWorks.tsx";

// Provided at build time; when absent (e.g. local dev) the login screen shows an
// input so the client id can be pasted, mirroring the PoC.
const ENV_CLIENT_ID = (import.meta.env as unknown as { VITE_GOOGLE_CLIENT_ID?: string })
  .VITE_GOOGLE_CLIENT_ID;
// Re-request the token when under a minute of its ~1h life remains.
const TOKEN_MARGIN_MS = 60_000;

type Phase = "idle" | "syncing" | "done" | "error";

interface Token {
  value: string;
  expiresAt: number; // epoch ms
}

// One plot per line: compact but diff-friendly, matching the old copy format the
// IITC plugin already parses.
function plotsJson(plots: Plot[]): string {
  return plots.length === 0 ? "[]" : `[\n${plots.map((p) => JSON.stringify(p)).join(",\n")}\n]`;
}

export default function App() {
  const [clientId, setClientId] = useState(ENV_CLIENT_ID ?? "");
  const [token, setToken] = useState<Token | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [authError, setAuthError] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [progress, setProgress] = useState<SyncProgress | null>(null);
  const [result, setResult] = useState<FullSyncResult | null>(null);
  const [syncError, setSyncError] = useState("");
  const [copyMessage, setCopyMessage] = useState("");

  // Reuse the in-memory token while it is comfortably valid; otherwise ask GIS
  // for a fresh one (silent when the Google session is still active).
  async function acquireToken(): Promise<string> {
    if (token && token.expiresAt - Date.now() > TOKEN_MARGIN_MS) return token.value;
    const r = await requestAccessToken(clientId);
    setToken({ value: r.accessToken, expiresAt: Date.now() + r.expiresIn * 1000 });
    return r.accessToken;
  }

  async function handleLogin() {
    setAuthError("");
    try {
      const r = await requestAccessToken(clientId);
      setToken({ value: r.accessToken, expiresAt: Date.now() + r.expiresIn * 1000 });
      setProfile(await fetchProfile(r.accessToken));
    } catch (e) {
      setAuthError(e instanceof Error ? e.message : "Sign-in failed.");
    }
  }

  function handleLogout() {
    setToken(null);
    setProfile(null);
    setResult(null);
    setProgress(null);
    setPhase("idle");
    setCopyMessage("");
  }

  async function handleSync() {
    setPhase("syncing");
    setSyncError("");
    setProgress(null);
    setCopyMessage("");
    try {
      const accessToken = await acquireToken();
      // Runs on the main thread: the HTML decoder needs DOMParser/document.evaluate,
      // which don't exist in a Web Worker. Work is network-bound and awaits between
      // batches, so progress renders and the UI stays responsive.
      const res = await runFullSync({ accessToken, onProgress: setProgress });
      setResult(res);
      setPhase("done");
    } catch (e) {
      setSyncError(e instanceof Error ? e.message : "Sync failed.");
      setPhase("error");
    }
  }

  async function handleCopy() {
    if (!result) return;
    try {
      await navigator.clipboard.writeText(plotsJson(result.plots));
      setCopyMessage(`Copied ${result.plots.length} plots to clipboard.`);
    } catch {
      setCopyMessage("Clipboard was blocked — click Copy again.");
    }
  }

  if (!profile) {
    return (
      <div className="container">
        <h1 className="title">Damage Report Plots</h1>
        <HowItWorks />
        {!ENV_CLIENT_ID && (
          <input
            className="client-id"
            placeholder="Google OAuth Client ID"
            value={clientId}
            onChange={(e) => setClientId(e.target.value)}
          />
        )}
        <button onClick={handleLogin} className="google-signin" disabled={!clientId}>
          <img src={googleSignin} alt="Sign in with Google" height={40} />
        </button>
        {authError && <p className="message error">{authError}</p>}
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

      <button onClick={handleSync} disabled={syncing} className="btn primary">
        {syncing ? "Syncing…" : "Sync Gmail → Sheet"}
      </button>

      {/* Fixed message slot so the layout doesn't jump. */}
      <p className={`message ${phase === "error" ? "error" : "success"}`}>
        {phase === "error"
          ? syncError
          : phase === "done"
            ? `Synced. ${result?.appended ?? 0} new report${result?.appended === 1 ? "" : "s"}.` +
              (result?.truncated ? " More history remains — Sync again to continue." : "")
            : ""}
      </p>

      {syncing && progress && (
        <div className="status-card">
          <p className="status-label">
            {progress.phase === "list" ? "Listing threads" : "Fetching threads"} · window{" "}
            {new Date(progress.windowStart * 1000).toLocaleDateString()}
          </p>
          <p className="status-label">
            threads {progress.threadsProcessed} / {progress.threadsFound} · portals{" "}
            {progress.portalsFound}
          </p>
        </div>
      )}

      <button onClick={handleCopy} disabled={!result} className="btn secondary">
        Copy plots JSON
      </button>
      <p className="message success">{copyMessage}</p>

      {result && (
        <p className="status-label">{result.plots.length} plots in your spreadsheet.</p>
      )}
    </div>
  );
}
