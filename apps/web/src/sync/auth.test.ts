import { describe, it, expect } from "vitest";
import { LOGIN_SCOPE, SYNC_SCOPE, requestAccessToken, type GisOAuth2 } from "./auth";

function fakeOAuth2(response: {
  access_token?: string;
  expires_in?: number;
  scope?: string;
  error?: string;
}): GisOAuth2 {
  return {
    initTokenClient: (cfg) => ({ requestAccessToken: () => cfg.callback(response) }),
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
});
