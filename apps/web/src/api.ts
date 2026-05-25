export interface Profile {
  id: string;
  email: string;
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
  const data = await res.json() as { id: string; email: string; name: string; picture: string };
  return data;
}

export async function sync(): Promise<void> {
  const res = await request("/api/v1/sync", { method: "POST" });
  if (!res.ok) {
    const body = await res.json() as { error?: string };
    throw new Error(body.error ?? `Sync failed: ${res.status}`);
  }
}

export async function logout(): Promise<void> {
  await request("/auth/logout", { method: "DELETE" });
}

export interface ApplicationStatus {
  sqs_queues: {
    thread_ids: number;
    reports: number;
  };
}

export async function getApplicationStatus(): Promise<ApplicationStatus> {
  const res = await request("/api/v1/application_status");
  if (!res.ok) throw new Error(`Status fetch failed: ${res.status}`);
  return res.json() as Promise<ApplicationStatus>;
}

export interface UserStatus {
  last_synced_at: number | null;
  spreadsheet_exists: boolean;
  scope_expires_at: {
    spreadsheets: number | null;
    sync: number | null;
  };
}

export async function getUserStatus(): Promise<UserStatus> {
  const res = await request("/api/v1/user_status");
  if (!res.ok) throw new Error(`User status fetch failed: ${res.status}`);
  return res.json() as Promise<UserStatus>;
}
