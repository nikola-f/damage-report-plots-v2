import { useEffect, useState } from "react";
import { getProfile, logout, sync, type Profile } from "./api.ts";

type Status = "idle" | "loading" | "success" | "error";

export default function App() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [syncStatus, setSyncStatus] = useState<Status>("idle");
  const [syncMessage, setSyncMessage] = useState("");

  useEffect(() => {
    getProfile()
      .then(setProfile)
      .catch(console.error)
      .finally(() => setAuthLoading(false));
  }, []);

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

      <button onClick={handleLogout} style={styles.buttonSecondary}>
        Logout
      </button>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  center: { textAlign: "center", marginTop: "4rem", color: "#666" },
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
  email: { margin: 0, color: "#666", fontSize: "0.875rem" },
  button: {
    padding: "0.625rem 1.25rem",
    background: "#4285f4",
    color: "#fff",
    border: "none",
    borderRadius: 6,
    cursor: "pointer",
    fontSize: "1rem",
  },
  buttonSecondary: {
    padding: "0.5rem 1rem",
    background: "transparent",
    color: "#666",
    border: "1px solid #ccc",
    borderRadius: 6,
    cursor: "pointer",
    fontSize: "0.875rem",
  },
  success: { color: "#1a7f37", margin: 0 },
  error: { color: "#cf222e", margin: 0 },
};
