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
| `openid` / `email` / `profile` | Non-sensitive | No |
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

> Damage Report Plots uses `gmail.readonly` for one user-facing feature: reading
> the user's own "Ingress Damage Report" emails to extract the list of attacked
> in-game portals and their coordinates.
>
> The Gmail query is tightly scoped to these emails only — subject
> "Ingress Damage Report: Entities attacked by" from the official Ingress senders
> `ingress-support@google.com`, `ingress-support@nianticlabs.com`, and
> `ingress-support@nianticspatial.com` — so the app reads no other mail.
>
> The app needs the **message body** (the HTML table listing the portals), which
> requires read access to message content. `gmail.metadata` is insufficient
> because it cannot return the body, and there is no read-only Gmail scope
> narrower than `gmail.readonly` that returns message bodies. Access is strictly
> read-only: the app never sends, modifies, labels, or deletes any email.
>
> All reading and parsing happen in the user's browser. Message content and
> anything derived from it are never transmitted to, stored on, or logged by any
> server operated by us — the only destination for the extracted data is a Google
> Sheet in the user's own Google Drive. Use of this data complies with the Google
> API Services User Data Policy, including the Limited Use requirements.

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

### `email` / `profile` (non-sensitive)

> Used only to display the signed-in user's basic identity (name, email address,
> profile picture) in the app UI.

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

- **Homepage**: the app root on the verified prod domain (`https://<prod-domain>/`).
- **App description**: `https://<prod-domain>/about.html` (D2).
- **Privacy policy**: `https://<prod-domain>/privacy.html` (D1).
- **Demo video**: unlisted YouTube URL (D6).
