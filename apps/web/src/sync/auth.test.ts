import { describe, it, expect, vi } from "vitest";
import {
  LOGIN_SCOPE,
  REGISTERED_SCOPES,
  SYNC_SCOPE,
  missingScopes,
  SHEET_SCOPE,
  PROMPT_IF_NEEDED,
  REVOKE_TIMEOUT_MS,
  requestAccessToken,
  revokeAccessToken,
  type GisOAuth2,
} from "./auth";

// What Google actually returns for LOGIN_SCOPE: the shorthand expanded to full
// URLs, plus openid.
const GRANTED_LOGIN_SCOPE = [
  "openid",
  "https://www.googleapis.com/auth/userinfo.profile",
  "https://www.googleapis.com/auth/drive.file",
].join(" ");

// A user who signed in before `email` was dropped keeps it in their grant, so
// Google keeps returning it. Extra scopes must not be mistaken for a problem.
const GRANTED_WITH_STALE_EMAIL = [
  GRANTED_LOGIN_SCOPE,
  "https://www.googleapis.com/auth/userinfo.email",
].join(" ");

function fakeOAuth2(
  response: {
    access_token?: string;
    expires_in?: number;
    scope?: string;
    error?: string;
  },
  revoke: GisOAuth2["revoke"] = () => {},
  onRequest?: (overrides?: { prompt?: string }) => void,
): GisOAuth2 {
  return {
    initTokenClient: (cfg) => ({
      requestAccessToken: (overrides) => {
        onRequest?.(overrides);
        cfg.callback(response);
      },
    }),
    revoke,
  };
}

describe("scopes (incremental authorization)", () => {
  it("login asks for identity + drive.file but not the restricted gmail scope", () => {
    expect(LOGIN_SCOPE).toContain("userinfo.profile");
    expect(LOGIN_SCOPE).toContain("drive.file");
    expect(LOGIN_SCOPE).not.toContain("gmail.readonly");
  });

  // OAuth verification requires a strict string match between the authorization
  // request and the console's Data Access registration. The first submission was
  // rejected for asking `profile` while the console held the expanded URL, so
  // this guards the union rather than any single set.
  it("asks for exactly the scopes registered in the Cloud Console", () => {
    const requested = new Set([...LOGIN_SCOPE.split(" "), ...SYNC_SCOPE.split(" "), ...SHEET_SCOPE.split(" ")]);
    expect([...requested].sort()).toEqual([...REGISTERED_SCOPES].sort());
  });

  // The shorthand is what Google expands on its side; asking with it is what
  // produced the mismatch.
  it("never asks with the `profile` shorthand", () => {
    for (const scope of [LOGIN_SCOPE, SYNC_SCOPE, SHEET_SCOPE]) {
      expect(scope.split(" ")).not.toContain("profile");
    }
  });

  it("login does not ask for the address: the UI shows only a name and picture", () => {
    expect(LOGIN_SCOPE).not.toContain("email");
  });

  // Every read-only Drive scope covers the whole of a user's Drive and is
  // restricted, which would trigger the CASA assessment this design avoids.
  // drive.file is the narrowest scope that reaches the app's own spreadsheet.
  it("uses no restricted Drive scope in place of drive.file", () => {
    for (const scope of [LOGIN_SCOPE, SYNC_SCOPE]) {
      expect(scope).not.toContain("auth/drive.readonly");
      expect(scope).not.toContain("auth/drive.metadata");
    }
  });

  // What lets App.acquireToken serve the Copy button from whichever token is
  // already in hand, instead of sending the user to GIS for a third one.
  it("covers the sheet scope from both the login and the sync token", () => {
    expect(missingScopes(SHEET_SCOPE, LOGIN_SCOPE)).toEqual([]);
    expect(missingScopes(SHEET_SCOPE, SYNC_SCOPE)).toEqual([]);
  });

  it("sync adds gmail.readonly and keeps drive.file for writing the sheet", () => {
    expect(SYNC_SCOPE).toContain("gmail.readonly");
    expect(SYNC_SCOPE).toContain("drive.file");
  });

  it("neither scope uses the sensitive spreadsheets scope", () => {
    expect(LOGIN_SCOPE).not.toContain("auth/spreadsheets");
    expect(SYNC_SCOPE).not.toContain("auth/spreadsheets");
  });
});

describe("requestAccessToken", () => {
  it("resolves with the token on success", async () => {
    const oauth2 = fakeOAuth2({ access_token: "tok", expires_in: 3599, scope: LOGIN_SCOPE });
    await expect(requestAccessToken("cid", {}, oauth2)).resolves.toMatchObject({
      accessToken: "tok",
      expiresIn: 3599,
    });
  });

  it("rejects on an error response", async () => {
    const oauth2 = fakeOAuth2({ error: "access_denied" });
    await expect(requestAccessToken("cid", {}, oauth2)).rejects.toThrow("access_denied");
  });

  it("rejects when no access_token is returned", async () => {
    const oauth2 = fakeOAuth2({ expires_in: 10 });
    await expect(requestAccessToken("cid", {}, oauth2)).rejects.toThrow(/no access_token/);
  });

  it("accepts the expanded scope string Google really returns", async () => {
    const oauth2 = fakeOAuth2({ access_token: "tok", scope: GRANTED_LOGIN_SCOPE });
    await expect(requestAccessToken("cid", { scope: LOGIN_SCOPE }, oauth2)).resolves.toMatchObject({
      accessToken: "tok",
    });
  });

  // PROMPT_IF_NEEDED is the empty string, so a truthiness check would drop it
  // and leave GIS on its 'select_account' default — an account chooser in front
  // of every Sync and Copy.
  it("forwards an empty prompt instead of treating it as unset", async () => {
    const onRequest = vi.fn();
    const oauth2 = fakeOAuth2({ access_token: "tok", scope: SYNC_SCOPE }, () => {}, onRequest);
    await requestAccessToken("cid", { scope: SYNC_SCOPE, prompt: PROMPT_IF_NEEDED }, oauth2);
    expect(onRequest).toHaveBeenCalledWith({ prompt: "" });
  });

  it("leaves the GIS default in place when no prompt is given", async () => {
    const onRequest = vi.fn();
    const oauth2 = fakeOAuth2({ access_token: "tok", scope: GRANTED_LOGIN_SCOPE }, () => {}, onRequest);
    await requestAccessToken("cid", { scope: LOGIN_SCOPE }, oauth2);
    expect(onRequest).toHaveBeenCalledWith(undefined);
  });

  it("rejects a token issued without the Gmail scope the user unchecked", async () => {
    const oauth2 = fakeOAuth2({
      access_token: "tok",
      scope: "https://www.googleapis.com/auth/drive.file",
    });
    await expect(requestAccessToken("cid", { scope: SYNC_SCOPE }, oauth2)).rejects.toThrow(
      /read Gmail messages/,
    );
  });
});

describe("missingScopes", () => {
  it("treats the email/profile shorthand as granted when Google expands it", () => {
    expect(missingScopes(LOGIN_SCOPE, GRANTED_LOGIN_SCOPE)).toEqual([]);
  });

  it("reports a scope the user cleared on the granular consent screen", () => {
    expect(missingScopes(SYNC_SCOPE, "https://www.googleapis.com/auth/drive.file")).toEqual([
      "https://www.googleapis.com/auth/gmail.readonly",
    ]);
  });

  it("reports everything when the granted list is empty", () => {
    expect(missingScopes(SYNC_SCOPE, "")).toHaveLength(2);
  });

  it("ignores extra scopes Google adds", () => {
    expect(missingScopes("profile", "openid profile")).toEqual([]);
  });

  it("accepts a returning user whose grant still carries the dropped email scope", () => {
    expect(missingScopes(LOGIN_SCOPE, GRANTED_WITH_STALE_EMAIL)).toEqual([]);
  });
});

describe("revokeAccessToken", () => {
  it("hands the token to GIS and resolves once Google answers", async () => {
    const revoke = vi.fn((_token: string, done?: () => void) => done?.());
    await revokeAccessToken("tok", fakeOAuth2({}, revoke));
    expect(revoke).toHaveBeenCalledWith("tok", expect.any(Function));
  });

  // A blocked request (CSP, offline) leaves the GIS callback unfired. Signing
  // out must still finish, and the failure must not be silent.
  it("gives up with a warning when GIS never calls back", async () => {
    vi.useFakeTimers();
    try {
      const onTimeout = vi.fn();
      const settled = vi.fn();
      const pending = revokeAccessToken("tok", fakeOAuth2({}, () => {}), onTimeout).then(settled);

      await vi.advanceTimersByTimeAsync(REVOKE_TIMEOUT_MS);
      await pending;

      expect(onTimeout).toHaveBeenCalledOnce();
      expect(settled).toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });

  it("does not warn when GIS answers in time", async () => {
    vi.useFakeTimers();
    try {
      const onTimeout = vi.fn();
      await revokeAccessToken("tok", fakeOAuth2({}, (_t, done) => done?.()), onTimeout);
      await vi.advanceTimersByTimeAsync(REVOKE_TIMEOUT_MS * 2);
      expect(onTimeout).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });
});
