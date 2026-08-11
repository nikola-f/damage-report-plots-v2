import { describe, it, expect, vi } from "vitest";
import {
  LOGIN_SCOPE,
  SYNC_SCOPE,
  missingScopes,
  REVOKE_TIMEOUT_MS,
  requestAccessToken,
  revokeAccessToken,
  type GisOAuth2,
} from "./auth";

// What Google actually returns for LOGIN_SCOPE: the shorthand expanded to full
// URLs, plus openid.
const GRANTED_LOGIN_SCOPE = [
  "openid",
  "https://www.googleapis.com/auth/userinfo.email",
  "https://www.googleapis.com/auth/userinfo.profile",
  "https://www.googleapis.com/auth/drive.file",
].join(" ");

function fakeOAuth2(
  response: {
    access_token?: string;
    expires_in?: number;
    scope?: string;
    error?: string;
  },
  revoke: GisOAuth2["revoke"] = () => {},
): GisOAuth2 {
  return {
    initTokenClient: (cfg) => ({ requestAccessToken: () => cfg.callback(response) }),
    revoke,
  };
}

describe("scopes (incremental authorization)", () => {
  it("login asks for identity + drive.file but not the restricted gmail scope", () => {
    expect(LOGIN_SCOPE).toContain("email");
    expect(LOGIN_SCOPE).toContain("profile");
    expect(LOGIN_SCOPE).toContain("drive.file");
    expect(LOGIN_SCOPE).not.toContain("gmail.readonly");
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
