// Google Identity Services (GIS) token model. Runs entirely in the browser:
// PKCE, no client secret, no server round-trip. The returned access token —
// which grants the restricted gmail.readonly scope — never leaves the browser,
// which is what keeps the app out of CASA scope.

// gmail.readonly is the only restricted scope (client-side only). drive.file is
// non-sensitive and replaces the old sensitive `spreadsheets` scope: it lets the
// app create/read/write only its own spreadsheet AND rediscover it across
// devices (see drive.ts).
export const SCOPES = [
  "email",
  "profile",
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/drive.file",
].join(" ");

export interface TokenResult {
  accessToken: string;
  expiresIn: number; // seconds (typically 3599); no refresh token in this model
  scope: string;
}

interface GisTokenResponse {
  access_token?: string;
  expires_in?: number;
  scope?: string;
  error?: string;
}
interface GisTokenClient {
  requestAccessToken(overrides?: { prompt?: string }): void;
}
export interface GisOAuth2 {
  initTokenClient(config: {
    client_id: string;
    scope: string;
    callback: (response: GisTokenResponse) => void;
    error_callback?: (error: { type?: string; message?: string }) => void;
  }): GisTokenClient;
}

declare global {
  interface Window {
    google?: { accounts?: { oauth2?: GisOAuth2 } };
  }
}

const GIS_SRC = "https://accounts.google.com/gsi/client";
let gisPromise: Promise<GisOAuth2> | null = null;

// Lazily inject the GIS client script and resolve once google.accounts.oauth2
// is available. Cached so concurrent callers share one load.
export function loadGis(): Promise<GisOAuth2> {
  const ready = window.google?.accounts?.oauth2;
  if (ready) return Promise.resolve(ready);

  gisPromise ??= new Promise<GisOAuth2>((resolve, reject) => {
    const onload = () => {
      const oauth2 = window.google?.accounts?.oauth2;
      if (oauth2) resolve(oauth2);
      else reject(new Error("GIS loaded but google.accounts.oauth2 is unavailable"));
    };
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${GIS_SRC}"]`);
    if (existing) {
      existing.addEventListener("load", onload);
      existing.addEventListener("error", () => reject(new Error("failed to load GIS")));
      return;
    }
    const script = document.createElement("script");
    script.src = GIS_SRC;
    script.async = true;
    script.defer = true;
    script.onload = onload;
    script.onerror = () => reject(new Error("failed to load GIS"));
    document.head.appendChild(script);
  });
  return gisPromise;
}

// Request an access token. `oauth2` is injectable for tests; in the browser it
// defaults to the lazily-loaded GIS client.
export async function requestAccessToken(
  clientId: string,
  opts: { scope?: string; prompt?: string } = {},
  oauth2?: GisOAuth2,
): Promise<TokenResult> {
  const gis = oauth2 ?? (await loadGis());
  return new Promise<TokenResult>((resolve, reject) => {
    const client = gis.initTokenClient({
      client_id: clientId,
      scope: opts.scope ?? SCOPES,
      callback: (r) => {
        if (r.error || !r.access_token) {
          reject(new Error(r.error ?? "no access_token returned"));
          return;
        }
        resolve({ accessToken: r.access_token, expiresIn: r.expires_in ?? 0, scope: r.scope ?? "" });
      },
      error_callback: (e) => reject(new Error(e.message ?? e.type ?? "GIS error")),
    });
    client.requestAccessToken(opts.prompt ? { prompt: opts.prompt } : undefined);
  });
}
