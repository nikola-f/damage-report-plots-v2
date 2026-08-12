// Google Identity Services (GIS) token model. Runs entirely in the browser:
// PKCE, no client secret, no server round-trip. The returned access token —
// which grants the restricted gmail.readonly scope — never leaves the browser,
// which is what keeps the app out of CASA scope.

// gmail.readonly is the only restricted scope (client-side only). drive.file is
// non-sensitive and replaces the old sensitive `spreadsheets` scope: it lets the
// app create/read/write only its own spreadsheet AND rediscover it across
// devices (see drive.ts).
const GMAIL_READONLY = "https://www.googleapis.com/auth/gmail.readonly";
const DRIVE_FILE = "https://www.googleapis.com/auth/drive.file";

// Incremental authorization. At login we ask only for identity + the app's own
// Drive file; the restricted gmail.readonly scope is deferred to the start of a
// sync (SYNC_SCOPE), so users grant Gmail access only when they actually run one.
// In the GIS token model each token is valid only for the scopes requested, so
// SYNC_SCOPE also includes drive.file — a sync both reads Gmail and writes the
// spreadsheet.
// `email` is not requested: the UI shows the signed-in user's name and picture,
// both of which come from `profile`, and the address was never displayed.
//
// drive.file stays even though login only reads (find the spreadsheet, read the
// plots): Drive has no read-only equivalent scoped to the app's own files. The
// read-only alternatives — drive.readonly, drive.metadata.readonly — cover the
// user's entire Drive and are *restricted* scopes, so swapping one in would
// both widen the access and pull the app into the CASA assessment this design
// exists to avoid.
export const LOGIN_SCOPE = ["profile", DRIVE_FILE].join(" ");
export const SYNC_SCOPE = [GMAIL_READONLY, DRIVE_FILE].join(" ");

// Google expands the `email`/`profile` shorthand to these URLs in the granted
// scope string and adds `openid`, so a requested scope never comes back
// verbatim. Comparing the two lists without this mapping would report every
// login as partially granted. `email` is kept here because a returning user's
// grant may still carry it from before it was dropped.
const SCOPE_ALIASES: Record<string, string> = {
  email: "https://www.googleapis.com/auth/userinfo.email",
  profile: "https://www.googleapis.com/auth/userinfo.profile",
};

// What the user sees on the consent screen, for the error message below. Only
// the scopes this app can actually be refused are worth naming.
const SCOPE_LABELS: Record<string, string> = {
  [GMAIL_READONLY]: "read Gmail messages",
  [DRIVE_FILE]: "create and edit its own Google Sheet",
};

function canonical(scope: string): string {
  return SCOPE_ALIASES[scope] ?? scope;
}

function split(scopes: string): string[] {
  return scopes.split(/\s+/).filter(Boolean);
}

// Scopes that were asked for but not granted. Google's granular consent screen
// lets the user clear individual checkboxes and still issues a token — just a
// narrower one — so a successful callback is not evidence that the app can do
// its job. Without this check the app takes a Gmail-less token, caches it for
// its full hour, and every sync fails with an opaque `threads.list 403`.
export function missingScopes(requested: string, granted: string): string[] {
  const have = new Set(split(granted).map(canonical));
  return split(requested).filter((s) => !have.has(canonical(s)));
}

function describeMissing(missing: string[]): string {
  const parts = missing.map((s) => SCOPE_LABELS[s] ?? s);
  return (
    `Permission to ${parts.join(" and ")} was not granted. ` +
    "Try again and leave every checkbox ticked on the Google consent screen."
  );
}

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
  revoke(accessToken: string, done?: () => void): void;
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
  const scope = opts.scope ?? LOGIN_SCOPE;
  return new Promise<TokenResult>((resolve, reject) => {
    const client = gis.initTokenClient({
      client_id: clientId,
      scope,
      callback: (r) => {
        if (r.error || !r.access_token) {
          reject(new Error(r.error ?? "no access_token returned"));
          return;
        }
        // Reject rather than hand back a partial token: the caller caches by the
        // scope it asked for, so accepting one would pin the shortfall for the
        // token's whole lifetime.
        const missing = missingScopes(scope, r.scope ?? "");
        if (missing.length > 0) {
          reject(new Error(describeMissing(missing)));
          return;
        }
        resolve({ accessToken: r.access_token, expiresIn: r.expires_in ?? 0, scope: r.scope ?? "" });
      },
      error_callback: (e) => reject(new Error(e.message ?? e.type ?? "GIS error")),
    });
    client.requestAccessToken(opts.prompt ? { prompt: opts.prompt } : undefined);
  });
}

// Revoke the token at Google, which drops the whole grant for this client — the
// next sign-in shows the consent screen again. Clearing local state alone would
// leave the token usable until it expires (~1h) and the grant standing, which
// is not what someone signing out of a shared browser is asking for.
//
// Best-effort by design: the caller signs out regardless of the outcome, since
// a failed revoke must not strand the user in a signed-in UI.
//
// Bounded because "best-effort" must not mean "silent". GIS reaches
// oauth2.googleapis.com itself, so anything that stops that request — a CSP
// that omits the host, an offline browser — leaves its callback unfired and the
// promise pending forever, which is how the first version of this failed with
// nothing but a console entry from the CSP to show for it. On timeout the
// warning is the signal that the grant is still standing.
export const REVOKE_TIMEOUT_MS = 5_000;

export async function revokeAccessToken(
  accessToken: string,
  oauth2?: GisOAuth2,
  onTimeout: () => void = () =>
    console.warn("[auth] revoke did not complete; the Google grant may still be active"),
): Promise<void> {
  const gis = oauth2 ?? (await loadGis());
  await new Promise<void>((resolve) => {
    const timer = setTimeout(() => {
      onTimeout();
      resolve();
    }, REVOKE_TIMEOUT_MS);
    gis.revoke(accessToken, () => {
      clearTimeout(timer);
      resolve();
    });
  });
}
