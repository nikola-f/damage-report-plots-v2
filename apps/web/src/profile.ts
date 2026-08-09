// Fetch the signed-in user's basic identity from Google's OpenID userinfo
// endpoint using the client-side access token (email/profile scopes). Client
// only — no server, no restricted data.

export interface Profile {
  name: string;
  picture: string;
  email: string;
}

export async function fetchProfile(accessToken: string): Promise<Profile> {
  const res = await fetch("https://www.googleapis.com/oauth2/v3/userinfo", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`userinfo ${res.status}`);
  const data = (await res.json()) as { name?: string; picture?: string; email?: string };
  return { name: data.name ?? "", picture: data.picture ?? "", email: data.email ?? "" };
}
