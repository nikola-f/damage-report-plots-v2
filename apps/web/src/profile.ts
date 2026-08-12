// Fetch the signed-in user's basic identity from Google's OpenID userinfo
// endpoint using the client-side access token (the `profile` scope). Client
// only — no server, no restricted data.
//
// The email address is deliberately absent: showing who is signed in needs only
// a name and a picture, so the app does not request the `email` scope.

export interface Profile {
  name: string;
  picture: string;
}

export async function fetchProfile(accessToken: string): Promise<Profile> {
  const res = await fetch("https://www.googleapis.com/oauth2/v3/userinfo", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`userinfo ${res.status}`);
  const data = (await res.json()) as { name?: string; picture?: string };
  return { name: data.name ?? "", picture: data.picture ?? "" };
}
