import { useEffect, useState } from "react";
import { getPlots, getProfile, getStatus, grantSpreadsheets, grantSync, logout, sync, type Profile, type Status as AppStatus } from "./api.ts";

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

function queueLevel(available: number): QueueLevel {
  if (available <= QUEUE_GREEN_MAX) return "green";
  if (available < QUEUE_RED_MIN) return "yellow";
  return "red";
}

const LEVEL_COLOR: Record<QueueLevel, string> = {
  green: "#3fb950",
  yellow: "#d29922",
  red: "#f85149",
};

const LEVEL_LABEL: Record<QueueLevel, string> = {
  green: "Idle",
  yellow: "Busy",
  red: "Congested",
};

export default function App() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [syncStatus, setSyncStatus] = useState<SyncStatus>("idle");
  const [syncMessage, setSyncMessage] = useState("");
  const [queueStatus, setQueueStatus] = useState<QueueLevel | null>(null);
  const [status, setStatus] = useState<AppStatus | null>(null);
  const [copyStatus, setCopyStatus] = useState<SyncStatus>("idle");
  const [copyMessage, setCopyMessage] = useState("");

  useEffect(() => {
    getProfile()
      .then(setProfile)
      .catch(console.error)
      .finally(() => setAuthLoading(false));
  }, []);

  async function refreshStatus(): Promise<AppStatus> {
    const s = await getStatus();
    setStatus(s);
    const total = s.app.sqs_queues.thread_ids + s.app.sqs_queues.reports;
    setQueueStatus(queueLevel(total));
    return s;
  }

  useEffect(() => {
    if (!profile) {
      setQueueStatus(null);
      setStatus(null);
      return;
    }

    refreshStatus().catch(console.error);
    const timerId = setInterval(
      () => refreshStatus().catch(console.error),
      STATUS_POLL_INTERVAL_MS,
    );
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
        // none, so prompt the user to click again (the token is now valid).
        setCopyStatus("error");
        setCopyMessage('Ready. Click "Copy plots JSON" again to copy.');
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : "Copy failed.";
      if (message === "reauthorization_required") {
        try {
          const authorizationUrl = await grantSpreadsheets();
          sessionStorage.setItem(PENDING_COPY_KEY, "1");
          window.location.href = authorizationUrl;
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

  if (authLoading) {
    return <p style={styles.center}>Loading…</p>;
  }

  if (!profile) {
    return (
      <div style={styles.container}>
        <h1 style={styles.title}>Damage Report Plots</h1>
        <button onClick={handleLogin} style={styles.button}>
          Login with Google
        </button>
      </div>
    );
  }

  return (
    <div style={styles.container}>
      <h1 style={styles.title}>Damage Report Plots</h1>

      <div style={styles.profile}>
        <img src={profile.picture} alt={profile.name} style={styles.avatar} />
        <div>
          <p style={styles.name}>{profile.name}</p>
        </div>
      </div>

      <button
        onClick={handleSync}
        disabled={syncStatus === "loading"}
        style={styles.button}
      >
        {syncStatus === "loading" ? "Syncing…" : "Sync Gmail → Sheets"}
      </button>

      {syncMessage && (
        <p style={syncStatus === "error" ? styles.error : styles.success}>
          {syncMessage}
        </p>
      )}

      <button
        onClick={runCopy}
        disabled={copyStatus === "loading"}
        style={styles.buttonSecondary}
      >
        {copyStatus === "loading" ? "Copying…" : "Copy plots JSON"}
      </button>

      {copyMessage && (
        <p style={copyStatus === "error" ? styles.error : styles.success}>
          {copyMessage}
        </p>
      )}

      {queueStatus && (
        <div style={styles.statusRow}>
          <span
            style={{
              ...styles.statusDot,
              background: LEVEL_COLOR[queueStatus],
            }}
          />
          <span style={styles.statusLabel}>
            Queue: {LEVEL_LABEL[queueStatus]}
          </span>
        </div>
      )}

      {status !== null && (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.25rem" }}>
          <p style={{ ...styles.statusLabel, margin: 0 }}>
            Sync started: {status.user.last_synced_at
              ? new Date(status.user.last_synced_at * 1000).toLocaleString()
              : "Never"}
          </p>
          <p style={{ ...styles.statusLabel, margin: 0 }}>
            Sync finished: {status.user.last_processed_at
              ? new Date(status.user.last_processed_at * 1000).toLocaleString()
              : "—"}
          </p>
          <p style={{ ...styles.statusLabel, margin: 0 }}>
            Latest report: {status.user.threads_max_internal_date
              ? new Date(status.user.threads_max_internal_date * 1000).toLocaleString()
              : "—"}
          </p>
        </div>
      )}

      <button onClick={handleLogout} style={styles.buttonSecondary}>
        Logout
      </button>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  center: { textAlign: "center", marginTop: "4rem", color: "#8a8f83" },
  container: {
    maxWidth: 480,
    margin: "4rem auto",
    padding: "2rem",
    fontFamily: "system-ui, sans-serif",
    display: "flex",
    flexDirection: "column",
    gap: "1rem",
  },
  title: { fontSize: "1.5rem", fontWeight: 700, margin: 0 },
  profile: { display: "flex", alignItems: "center", gap: "0.75rem" },
  avatar: { width: 48, height: 48, borderRadius: "50%" },
  name: { margin: 0, fontWeight: 600 },
  button: {
    padding: "0.625rem 1.25rem",
    background: "#5AB5B2",
    color: "#0F0F0F",
    border: "none",
    borderRadius: 6,
    cursor: "pointer",
    fontSize: "1rem",
  },
  buttonSecondary: {
    padding: "0.5rem 1rem",
    background: "transparent",
    color: "#EEF0E3",
    border: "1px solid #333",
    borderRadius: 6,
    cursor: "pointer",
    fontSize: "0.875rem",
  },
  success: { color: "#3fb950", margin: 0 },
  error: { color: "#f85149", margin: 0 },
  statusRow: { display: "flex", alignItems: "center", gap: "0.5rem" },
  statusDot: { width: 10, height: 10, borderRadius: "50%", flexShrink: 0 } as React.CSSProperties,
  statusLabel: { fontSize: "0.8rem", color: "#8a8f83" },
};
