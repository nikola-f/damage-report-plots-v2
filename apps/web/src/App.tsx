import { useEffect, useRef, useState } from "react";
import { getApplicationStatus, getProfile, logout, sync, type Profile } from "./api.ts";

type Status = "idle" | "loading" | "success" | "error";
type QueueLevel = "green" | "yellow" | "red";

const QUEUE_POLL_INTERVAL_MS = 60_000;
const QUEUE_GREEN_MAX = 10;
const QUEUE_RED_MIN = 61;

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
  const [syncStatus, setSyncStatus] = useState<Status>("idle");
  const [syncMessage, setSyncMessage] = useState("");
  const [queueStatus, setQueueStatus] = useState<QueueLevel | null>(null);
  const queueTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    getProfile()
      .then(setProfile)
      .catch(console.error)
      .finally(() => setAuthLoading(false));
  }, []);

  useEffect(() => {
    if (!profile) {
      setQueueStatus(null);
      if (queueTimerRef.current) clearInterval(queueTimerRef.current);
      return;
    }

    function fetchStatus() {
      getApplicationStatus()
        .then((s) => {
          const total = s.sqs_queues.thread_ids + s.sqs_queues.reports;
          setQueueStatus(queueLevel(total));
        })
        .catch(console.error);
    }

    fetchStatus();
    queueTimerRef.current = setInterval(fetchStatus, QUEUE_POLL_INTERVAL_MS);
    return () => { if (queueTimerRef.current) clearInterval(queueTimerRef.current); };
  }, [profile]);

  function handleLogin() {
    window.location.href = "/auth/google_oauth2";
  }

  async function handleLogout() {
    await logout();
    setProfile(null);
  }

  async function handleSync() {
    setSyncStatus("loading");
    setSyncMessage("");
    try {
      await sync();
      setSyncStatus("success");
      setSyncMessage("Sync started successfully.");
    } catch (err) {
      setSyncStatus("error");
      setSyncMessage(err instanceof Error ? err.message : "Sync failed.");
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
          <p style={styles.email}>{profile.email}</p>
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
  email: { margin: 0, color: "#8a8f83", fontSize: "0.875rem" },
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
