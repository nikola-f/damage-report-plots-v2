import { useEffect, useRef, useState } from "react";
import { getPlots, getProfile, getStatus, grantSpreadsheets, grantSync, logout, sync, type Profile, type Status as AppStatus } from "./api.ts";
// Pre-approved "Sign in with Google" asset (dark theme, Android+Web @4x,
// 720x160 shown at 180x40) from
// https://developers.google.com/identity/branding-guidelines — do not restyle.
import googleSignin from "./assets/google-signin-dark.png";
import HowItWorks from "./HowItWorks.tsx";

type SyncStatus = "idle" | "loading" | "success" | "error";
type QueueLevel = "green" | "yellow" | "red";

const STATUS_POLL_INTERVAL_MS = 10_000;
// Marks that a sync was requested before redirecting through Google to refresh
// the access token; the flow resumes here once we land back on the SPA.
const PENDING_SYNC_KEY = "pendingSync";
// Same idea for a "copy plots JSON" request that hit an expired token and had to
// re-acquire the spreadsheets scope before reading the sheet.
const PENDING_COPY_KEY = "pendingCopy";
const QUEUE_GREEN_MAX = 10;
const QUEUE_RED_MIN = 61;
// Minimum remaining token lifetime to run sync without re-authorizing first;
// workers keep using the token while the pipeline drains, so it must outlive
// the whole run, not just the POST /api/v1/sync call.
const SYNC_TOKEN_MARGIN_S = 30 * 60;
// Copy only needs the token for the immediate sheet read, so a minute of
// leeway is plenty; below that the plots request is doomed, so skip it and
// re-authorize directly.
const COPY_TOKEN_MARGIN_S = 60;

function queueLevel(available: number): QueueLevel {
  if (available <= QUEUE_GREEN_MAX) return "green";
  if (available < QUEUE_RED_MIN) return "yellow";
  return "red";
}

const LEVEL_LABEL: Record<QueueLevel, string> = {
  green: "Idle",
  yellow: "Busy",
  red: "Congested",
};

function formatEpoch(epoch: number | null): string {
  return epoch ? new Date(epoch * 1000).toLocaleString() : "—";
}

export default function App() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [syncStatus, setSyncStatus] = useState<SyncStatus>("idle");
  const [syncMessage, setSyncMessage] = useState("");
  const [status, setStatus] = useState<AppStatus | null>(null);
  const [statusUnavailable, setStatusUnavailable] = useState(false);
  const [copyStatus, setCopyStatus] = useState<SyncStatus>("idle");
  const [copyMessage, setCopyMessage] = useState("");
  // Plots JSON fetched by the post-redirect resume but not yet copied: the
  // Clipboard API needs a user gesture, so the next click writes this
  // directly instead of refetching.
  const readiedCopyRef = useRef<{ json: string; count: number } | null>(null);

  useEffect(() => {
    getProfile()
      .then(setProfile)
      .catch(console.error)
      .finally(() => setAuthLoading(false));
  }, []);

  async function refreshStatus(): Promise<AppStatus> {
    const s = await getStatus();
    setStatus(s);
    setStatusUnavailable(false);
    return s;
  }

  useEffect(() => {
    if (!profile) {
      setStatus(null);
      setStatusUnavailable(false);
      return;
    }

    // Keep the last known status on failure (timestamps stay useful); the
    // queue row switches to "Unavailable" until a poll succeeds again.
    const poll = () =>
      refreshStatus().catch((err) => {
        console.error(err);
        setStatusUnavailable(true);
      });

    poll();
    const timerId = setInterval(poll, STATUS_POLL_INTERVAL_MS);
    return () => clearInterval(timerId);
  }, [profile]);

  // Resume a sync that was queued before the token-refresh redirect.
  useEffect(() => {
    if (!profile) return;
    if (sessionStorage.getItem(PENDING_SYNC_KEY) !== "1") return;
    sessionStorage.removeItem(PENDING_SYNC_KEY);
    runSync();
  }, [profile]);

  // Resume a plots copy that was queued before the spreadsheets re-auth redirect.
  useEffect(() => {
    if (!profile) return;
    if (sessionStorage.getItem(PENDING_COPY_KEY) !== "1") return;
    sessionStorage.removeItem(PENDING_COPY_KEY);
    runCopy();
  }, [profile]);

  function handleLogin() {
    window.location.href = "/auth/google_oauth2";
  }

  async function handleLogout() {
    await logout();
    readiedCopyRef.current = null;
    setProfile(null);
  }

  // Refresh the access token (TTL counts from now), then resume the sync after
  // Google redirects us back. The redirect unloads the page, so the actual
  // POST /api/v1/sync happens in runSync on return.
  async function redirectToSyncGrant() {
    const authorizationUrl = await grantSync();
    sessionStorage.setItem(PENDING_SYNC_KEY, "1");
    window.location.href = authorizationUrl;
  }

  // Sync directly when the current token comfortably outlives the pipeline
  // (enough TTL left, queues near-idle); otherwise re-authorize via Google
  // first so the workers get a fresh token.
  async function handleSync() {
    setSyncStatus("loading");
    setSyncMessage("");
    try {
      let direct = false;
      try {
        const s = await refreshStatus();
        const expiresAt = s.user.scope_expires_at.sync;
        const total = s.app.sqs_queues.thread_ids + s.app.sqs_queues.reports;
        direct =
          expiresAt !== null &&
          expiresAt * 1000 - Date.now() >= SYNC_TOKEN_MARGIN_S * 1000 &&
          queueLevel(total) === "green";
      } catch {
        // Can't tell whether the token is still fresh; take the redirect path.
      }
      if (direct) {
        await runSync({ allowReauthRedirect: true });
      } else {
        await redirectToSyncGrant();
      }
    } catch (err) {
      setSyncStatus("error");
      setSyncMessage(err instanceof Error ? err.message : "Sync failed.");
    }
  }

  async function runSync({ allowReauthRedirect = false } = {}) {
    setSyncStatus("loading");
    setSyncMessage("");
    try {
      await sync();
      setSyncStatus("success");
      setSyncMessage("Sync started successfully.");
      refreshStatus().catch(console.error);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Sync failed.";
      if (message === "reauthorization_required" && allowReauthRedirect) {
        // The token was evicted between the status check and the call; fall
        // back to the grant redirect once (the resume path clears the flag,
        // so this can't loop).
        try {
          await redirectToSyncGrant();
          return;
        } catch (grantErr) {
          setSyncStatus("error");
          setSyncMessage(grantErr instanceof Error ? grantErr.message : "Authorization failed.");
          return;
        }
      }
      setSyncStatus("error");
      // The server rejects sync when the Google token has been evicted. We just
      // returned from a re-auth redirect, so avoid looping: ask the user to retry.
      setSyncMessage(
        message === "reauthorization_required"
          ? "Authorization expired. Please reload the page and sync again."
          : message,
      );
    }
  }

  // Re-acquire the spreadsheets scope (mints a fresh access token) and resume
  // the copy after Google redirects us back.
  async function redirectToSpreadsheetsGrant() {
    const authorizationUrl = await grantSpreadsheets();
    sessionStorage.setItem(PENDING_COPY_KEY, "1");
    window.location.href = authorizationUrl;
  }

  // Button entry point. A copy readied by the post-redirect resume only needs
  // this click's gesture, no refetch. Otherwise, when the polled status shows
  // the spreadsheets token expired (or never granted), the plots request is
  // doomed — skip it and re-authorize right away.
  async function handleCopy() {
    const readied = readiedCopyRef.current;
    if (readied !== null) {
      readiedCopyRef.current = null;
      try {
        await navigator.clipboard.writeText(readied.json);
        setCopyStatus("success");
        setCopyMessage(`Copied ${readied.count} plots to clipboard.`);
        return;
      } catch {
        // Clipboard rejected despite the gesture; fall through to a full run.
      }
    }

    const expiresAt = status?.user.scope_expires_at.spreadsheets ?? null;
    const knownExpired =
      status !== null &&
      !statusUnavailable &&
      (expiresAt === null || expiresAt * 1000 - Date.now() < COPY_TOKEN_MARGIN_S * 1000);
    if (knownExpired) {
      setCopyStatus("loading");
      setCopyMessage("");
      try {
        await redirectToSpreadsheetsGrant();
      } catch (err) {
        setCopyStatus("error");
        setCopyMessage(err instanceof Error ? err.message : "Authorization failed.");
      }
      return;
    }

    await runCopy();
  }

  // Fetch the plots sheet and copy it to the clipboard as JSON. If the access
  // token has expired, re-acquire the spreadsheets scope and resume on return.
  async function runCopy() {
    setCopyStatus("loading");
    setCopyMessage("");
    try {
      const plots = await getPlots();
      // One record per line to keep it compact yet diff-friendly.
      const json = plots.length === 0
        ? "[]"
        : `[\n${plots.map((p) => JSON.stringify(p)).join(",\n")}\n]`;
      try {
        await navigator.clipboard.writeText(json);
        setCopyStatus("success");
        setCopyMessage(`Copied ${plots.length} plots to clipboard.`);
      } catch {
        // The Clipboard API needs a user gesture; the post-redirect resume has
        // none. Keep the JSON so the next click copies it without refetching.
        readiedCopyRef.current = { json, count: plots.length };
        setCopyStatus("error");
        setCopyMessage('Ready. Click "Copy plots JSON" again to copy.');
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : "Copy failed.";
      if (message === "reauthorization_required") {
        try {
          await redirectToSpreadsheetsGrant();
          return;
        } catch (grantErr) {
          setCopyStatus("error");
          setCopyMessage(grantErr instanceof Error ? grantErr.message : "Authorization failed.");
          return;
        }
      }
      setCopyStatus("error");
      setCopyMessage(message);
    }
  }

  const queueTotal = status
    ? status.app.sqs_queues.thread_ids + status.app.sqs_queues.reports
    : 0;
  const level = status ? queueLevel(queueTotal) : null;
  const threadsFound = status?.user.threads_found ?? 0;
  const threadsProcessed = status?.user.threads_processed ?? 0;
  const portalsAppended = status?.user.portals_appended ?? 0;
  // A run is in flight from POST /api/v1/sync (last_synced_at stamped, counters
  // reset) until the batch stage stamps last_processed_at. That stamp never
  // happens when a run finds zero threads, so also treat "queues drained and
  // every discovered thread processed" as finished.
  const syncInProgress =
    status !== null &&
    status.user.last_synced_at !== null &&
    (status.user.last_processed_at ?? 0) < status.user.last_synced_at &&
    !(queueTotal === 0 && threadsProcessed >= threadsFound);
  // threads_found keeps growing while the list stage runs, so the ratio can
  // temporarily drop; the width transition keeps that from looking jumpy.
  const progressPct = threadsFound > 0
    ? Math.min(100, (threadsProcessed / threadsFound) * 100)
    : 0;

  if (authLoading) {
    return <p className="center">Loading…</p>;
  }

  if (!profile) {
    return (
      <div className="container">
        <h1 className="title">Damage Report Plots</h1>
        <HowItWorks />
        <button onClick={handleLogin} className="google-signin">
          <img src={googleSignin} alt="Sign in with Google" height={40} />
        </button>
      </div>
    );
  }

  return (
    <div className="container">
      <header className="header">
        <h1 className="title">Damage Report Plots</h1>
        <div className="header-user">
          <img src={profile.picture} alt={profile.name} className="avatar" />
          <span className="name">{profile.name}</span>
          <button onClick={handleLogout} className="btn secondary">
            Logout
          </button>
        </div>
      </header>

      <button
        onClick={handleSync}
        disabled={syncStatus === "loading"}
        className="btn primary"
      >
        {syncStatus === "loading" ? "Syncing…" : "Sync Gmail → Sheets"}
      </button>

      {/* Message slots are always rendered at a fixed height so buttons below
          never shift when messages appear or clear. */}
      <p className={`message ${syncStatus === "error" ? "error" : "success"}`}>
        {syncMessage}
      </p>

      <button
        onClick={handleCopy}
        disabled={copyStatus === "loading"}
        className="btn secondary"
      >
        {copyStatus === "loading" ? "Copying…" : "Copy plots JSON"}
      </button>

      <p className={`message ${copyStatus === "error" ? "error" : "success"}`}>
        {copyMessage}
      </p>

      <div className="status-card">
        <div className="status-row">
          <span
            className={`status-dot ${statusUnavailable || level === null ? "muted" : level}`}
          />
          <span className="status-label">
            Queue: {statusUnavailable ? "Unavailable" : level === null ? "—" : LEVEL_LABEL[level]}
          </span>
        </div>

        <div className="progress-row">
          {syncInProgress && (
            <>
              <div className="progress-track">
                <div className="progress-fill" style={{ width: `${progressPct}%` }} />
              </div>
              <span className="status-label">
                threads {threadsProcessed} / {threadsFound} · portals {portalsAppended}
              </span>
            </>
          )}
        </div>

        <p className="status-label">
          Sync started: {formatEpoch(status?.user.last_synced_at ?? null)}
        </p>
        <p className="status-label">
          Sync finished: {formatEpoch(status?.user.last_processed_at ?? null)}
        </p>
        <p className="status-label">
          Latest report: {formatEpoch(status?.user.threads_max_internal_date ?? null)}
        </p>
      </div>
    </div>
  );
}
