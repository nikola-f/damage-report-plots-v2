# Google OAuth consent — verification submission copy

Reference text to paste into the **prod** GCP project's OAuth verification form
(APIs & Services → OAuth consent screen → scope justifications / "Data access"
review). **This is not a hosted web page** — it lives here only as the source of
truth for what we submit. Keep it in sync with the actual request in
[`apps/web/src/sync/query.ts`](../apps/web/src/sync/query.ts) and
[`apps/web/src/sync/auth.ts`](../apps/web/src/sync/auth.ts).

## Scopes requested

| Scope | Sensitivity | Needs justification |
|-------|-------------|---------------------|
| `openid` / `userinfo.profile` | Non-sensitive | No |
| `https://www.googleapis.com/auth/drive.file` | Non-sensitive (recommended) | Light |
| `https://www.googleapis.com/auth/gmail.readonly` | **Restricted** | **Yes — main review** |

Only **`gmail.readonly`** drives the restricted-scope review. Because the app
handles restricted data **entirely client-side** and never sends or stores it on
a server, it qualifies for the **CASA security-assessment exemption**; standard
OAuth verification (brand + scope review + demo video) still applies.

---

## App summary (paste into "App functionality" / overview)

Damage Report Plots is a client-side web app for Ingress players. Ingress emails
players a "Damage Report" whenever their portals are attacked. The app reads
those specific emails from the user's Gmail, extracts each attacked portal's name
and coordinates, records them in a Google Sheet the app creates in the user's own
Google Drive, and lets the user copy the resulting list to the clipboard to plot
as a heatmap in the IITC Ingress Intel map plugin. The app has no backend server;
all Gmail access and parsing happen in the user's browser.

---

## Per-scope justification

### `gmail.readonly` (restricted) — primary

**This is the text submitted on 2026-08-30**, after review round 1 rejected the
first attempt. The console's justification field caps at **1,000 characters**, so
this is written to that budget rather than trimmed from something longer.

> Our users play the game Ingress. When another player attacks one of their
> portals, Ingress emails them a "Damage Report". The user wants to see which of
> their portals are attacked, how often and how recently, as a heatmap on the
> Ingress Intel map.
>
> That information exists only inside the message body: an HTML table listing
> each attacked portal's name, latitude and longitude. It is not in the subject,
> headers or metadata. Reading the body is the feature itself; without it the app
> has nothing to show.
>
> The user clicks "Sync Gmail -> Sheet". The app finds these reports, parses each
> body, writes one row per attacked portal into a Google Sheet in the user's own
> Drive, and copies the list for the user to paste into our IITC map plugin.
>
> We search only for the subject "Ingress Damage Report: Entities attacked by"
> from the three official ingress-support addresses, so no other mail is fetched.
> gmail.metadata cannot return bodies, and no read-only Gmail scope is narrower
> than gmail.readonly.

**What the first version got wrong**: it opened with the API constraint — the
body is needed, `gmail.metadata` cannot return it — and never said what the user
gets. The reviewer's words were *"your justification should bridge the gap
between backend operations and the user experience"*. Everything factual in the
old text is still here; the order changed, and the user's goal now comes first.
The sentence carrying the argument is *"Reading the body is the feature itself"*.

**Why not a narrower scope**: the feature requires the email body, which only
`gmail.readonly` (or broader) can return. We request the narrowest read scope and
constrain it further with a sender+subject query.

### `drive.file` (non-sensitive)

> Used only to create and then re-open the single spreadsheet the app itself
> creates for the user's portal data. `drive.file` grants access limited to
> app-created files, so the app cannot see any of the user's other Drive files.
> A private `appProperties` marker on that spreadsheet lets the app find the same
> sheet again when the user signs in from another device, keeping one continuous
> record. This replaces the broader, sensitive `spreadsheets` scope.

### `openid` / `userinfo.profile` (non-sensitive)

> Used only to display the signed-in user's name and profile picture in the app
> UI, so they can see which account is connected. The app does not request the
> `email` scope, and does not use an ID token — `openid` is requested because
> Google adds it to the grant regardless, and the request has to match the
> console registration.

---

## Data-handling statement (paste into the data-access / security questions)

> The application has no backend. It runs as a static single-page app (S3 +
> CloudFront) and calls Google's APIs (Gmail, Drive, Sheets, Google Identity
> Services) directly from the user's browser. Authentication uses the Google
> Identity Services token model (PKCE, no client secret); the access token lives
> in memory for its ~1-hour lifetime only and no refresh token is issued.
>
> Google user data obtained via `gmail.readonly` is processed exclusively in the
> browser and is **never sent to, stored on, or logged by any server we operate**.
> The only persisted output is written to a Google Sheet in the user's own Drive,
> under the user's control. No Google user data is shared with third parties, used
> for advertising, or sold. Because no restricted-scope data is stored or
> transmitted on our servers, the app qualifies for the restricted-scope security
> assessment (CASA) exemption.

---

## Limited Use statement (verbatim, matches the privacy policy)

> Damage Report Plots' use and transfer of information received from Google APIs
> to any other app will adhere to the Google API Services User Data Policy,
> including the Limited Use requirements.

---

## Supporting links to provide on the consent screen

- **Homepage**: `https://plots.world/`
- **App description**: `https://plots.world/about.html` (D2).
- **Privacy policy**: `https://plots.world/privacy.html` (D1) — **with the
  extension**. The CloudFront SPA function rewrites extensionless paths to
  `index.html`, so `/privacy` serves the app and a reviewer following it never
  reaches the policy.
- **Demo video**: unlisted YouTube URL (D6). **Deliberately not recorded here** —
  this repo is public and the video is unlisted, so writing the link down would
  publish it. It is in the submission and in the reply thread.

---

## Review round 1 — rejected 2026-08-29, answered 2026-08-30

Submitted 2026-08-23; the reply came back nine days later. Worth keeping because
none of the three findings was about whether the app deserves the scope.

### Scope Discrepancy — the one that was a real defect

> ensuring that the scopes requested in your codebase or manifest exactly match
> your Google Cloud Console configuration

They did not. Sign-in asked for the `profile` shorthand while the console held
`https://www.googleapis.com/auth/userinfo.profile`, and `openid` was registered
but never requested — Google adds it when granting, *after* the authorization
request is built. So the grant always looked right and the app worked, while the
request could never match the registration. Fixed in #409/#410, and
`REGISTERED_SCOPES` in `auth.ts` now pins the four strings with a test.

The lesson generalises: **a scope that Google normalises on its side still has to
be spelled the console's way in the request.** Nothing in the running app reveals
the mismatch.

### Scope Justification — see the rewrite above

### Demo Video

> if the scopes are obscured, click "Show all services"

Take 2 holds both consent screens open and readable, and adds a segment showing a
real Damage Report email beside the spreadsheet row it produces — evidence for
the claim that the coordinates exist nowhere but the body. `docs/oauth-demo-video.md`
carries the shot list and the chapter marks.

Two things worth knowing for any future recording:

- The `gmail.readonly` screen is now preceded by Google's **"unverified app"
  interstitial**, because the app is In Production and under review. It has to be
  dismissed on camera to reach the consent screen; do not cut it.
- **No "Show all services" control appears** on either screen. With this few
  scopes nothing is collapsed, so there is nothing to expand — the requirement is
  conditional and is already satisfied. The reply says so explicitly, to
  forestall the assumption that it was skipped.

### Test Credentials

Answered **not applicable**: the app issues no credentials, has no local login,
no paywall and no phone verification — a reviewer signs in with their own Google
account. The reply states plainly that an account with no Ingress Damage Report
mail syncs successfully to an **empty** result, since otherwise a reviewer testing
with their own mailbox would read that as a broken app. It offers a seeded
account on request rather than building one up front.

### Field limits

Every free-text field in the verification form caps at **1,000 characters**. The
long-form copy in this document does not fit; the versions above are written to
that budget. When trimming, the two things to keep are the **CASA exemption
claim** and the **denial of third-party sharing, advertising and sale** — both
are load-bearing and neither is recoverable from the rest of the text.
