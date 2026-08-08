import { describe, it, expect } from "vitest";
import { SCOPES, requestAccessToken, type GisOAuth2 } from "./auth";

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

describe("SCOPES", () => {
  it("requests gmail.readonly and drive.file, and drops the sensitive spreadsheets scope", () => {
    expect(SCOPES).toContain("gmail.readonly");
    expect(SCOPES).toContain("drive.file");
    expect(SCOPES).not.toContain("auth/spreadsheets");
  });
});

describe("requestAccessToken", () => {
  it("resolves with the token on success", async () => {
    const oauth2 = fakeOAuth2({ access_token: "tok", expires_in: 3599, scope: SCOPES });
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
