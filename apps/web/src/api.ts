export interface Profile {
  id: string;
  name: string;
  picture: string;
}

async function request(path: string, options: RequestInit = {}): Promise<Response> {
  const res = await fetch(path, { credentials: "include", ...options });
  return res;
}

export async function getProfile(): Promise<Profile | null> {
  const res = await request("/api/v1/profile");
  if (res.status === 401) return null;
  if (!res.ok) throw new Error(`Profile fetch failed: ${res.status}`);
  const data = await res.json() as { id: string; name: string; picture: string };
  return data;
}

export async function sync(): Promise<void> {
  const res = await request("/api/v1/sync", { method: "POST" });
  if (!res.ok) {
    const body = await res.json() as { error?: string };
    throw new Error(body.error ?? `Sync failed: ${res.status}`);
  }
}

// Re-acquire the sync-scoped authorization so a fresh access token is minted
// (its TTL counts from now, not from login). Returns the URL to redirect to.
export async function grantSync(): Promise<string> {
  const res = await request("/auth/grant/sync", { method: "POST" });
  if (!res.ok) throw new Error(`Grant sync failed: ${res.status}`);
  const data = await res.json() as { authorization_url: string };
  return data.authorization_url;
}

export async function logout(): Promise<void> {
  await request("/auth/logout", { method: "DELETE" });
}

export interface Status {
  user: {
    last_synced_at: number | null;
    last_processed_at: number | null;
    spreadsheet_exists: boolean;
    threads_found: number | null;
    threads_processed: number | null;
    portals_found: number | null;
    portals_appended: number | null;
    threads_max_internal_date: number | null;
    scope_expires_at: {
      spreadsheets: number | null;
      sync: number | null;
    };
  };
  app: {
    sqs_queues: {
      thread_ids: number;
      reports: number;
    };
  };
}

export async function getStatus(): Promise<Status> {
  const res = await request("/api/v1/status");
  if (!res.ok) throw new Error(`Status fetch failed: ${res.status}`);
  return res.json() as Promise<Status>;
}
