# D6 — OAuth verification demo video: storyboard and script

Shot list and narration for the demo video attached to the **prod** OAuth
verification submission. Companion to
[`oauth-consent-verification.md`](./oauth-consent-verification.md) — the video
has to show what that document claims, so change both together.

**Record after prod cutover, not before.** The consent screen must belong to the
prod OAuth client and the app must be served from the verified prod domain
(Google: *"Must show the same application you have submitted for verification"*).
A recording made against dev shows a different client and origin.

---

## What Google requires

From [Verification requirements](https://support.google.com/cloud/answer/13464321),
verbatim:

- *"Must show the end-to-end flow of your app including the OAuth grant process"*
- *"Must show the same application you have submitted for verification (including app name, branding)"*
- *"Show the complete OAuth Consent Screen. The consent screen must also show the same exact scopes you are requesting"*
- *"Please ensure the language setting on the bottom-left corner of the consent screen is toggled to 'English'"*
- *"Must demonstrate the app functionalities that utilize the requested OAuth scopes"*

Upload as **unlisted** on YouTube and paste the link into the submission.

---

## The trap: this app asks for consent twice

Authorization is incremental ([`auth.ts`](../apps/web/src/sync/auth.ts)):

| When | Scopes |
|------|--------|
| Sign in | `email`, `profile`, `drive.file` |
| First **Sync** click | `gmail.readonly`, `drive.file` |

`gmail.readonly` — the only scope under restricted review — appears on the
**second** screen, which is only reached by clicking *Sync Gmail → Sheet*. A
video that stops after sign-in never shows the scope being reviewed, and will be
rejected. **Shot 5 is the one the whole submission rests on.**

This design is worth narrating rather than hiding: it shows Gmail access is
requested only at the moment it is used.

---

## Before recording

- [ ] **Revoke the app's existing access** for the recording account at
      [myaccount.google.com/permissions](https://myaccount.google.com/permissions).
      Without this, an account that has already granted the scopes is sent
      straight through and **neither consent screen appears**.
- [ ] Set the Google account's language to **English** (the consent screen's
      language toggle is bottom-left; it must read English).
- [ ] Sign out of the app, or use a fresh browser profile.
- [ ] Pick a recording account whose mailbox holds **a modest number of damage
      reports**. The sync is paced to Gmail's quota at ~1,200 threads/minute, so
      a large mailbox means minutes of watching a counter. A few hundred reports
      keeps shot 6 under a minute.
- [ ] Have the IITC intel map open in another tab, already logged in.
- [ ] Hide bookmarks, other tabs, notifications, and anything personal in the
      mailbox that might appear.
- [ ] Record at 1080p. Keep the **browser URL bar visible in every shot** — not
      strictly required, but it is how the reviewer confirms the origin is the
      verified domain.

---

## Shot list

Target length **4–5 minutes**. Times are cumulative and approximate.

| # | Time | On screen | Narration |
|---|------|-----------|-----------|
| 1 | 0:00 | Landing page at the prod URL, signed out. Title *Damage Report Plots* visible with the URL bar. | "This is Damage Report Plots, a web app for players of the game Ingress, at our verified domain." |
| 2 | 0:15 | Scroll the *How it works* explainer on the landing page. | "Ingress emails players a Damage Report whenever their in-game portals are attacked. The app reads only those emails, extracts the attacked portals, and plots them on a map." |
| 3 | 0:30 | Click the footer links **How it works** and **Privacy Policy**; show `/privacy.html`, scroll to the **Limited Use** section. Return. | "These are the homepage and privacy policy URLs on our consent screen. The privacy policy includes our Limited Use disclosure." |
| 4 | 0:50 | Click **Sign in with Google**. **Hold 5 seconds** on the consent screen: app name, the listed permissions, and the language toggle reading *English*. Grant. | "Signing in requests only basic profile information and `drive.file`, which is limited to files this app creates." |
| 5 | 1:20 | Signed-in view: header with the account, empty summary. Click **Sync Gmail → Sheet**. **Hold 5–8 seconds** on the second consent screen showing **Read all resources and their metadata (gmail.readonly)**. Grant. | "Gmail access is requested separately, only when the user starts a sync — this is the restricted scope under review. The app reads Gmail to find Ingress Damage Report messages." |
| 6 | 1:50 | Progress card advancing: `Fetching threads - window …`, `threads 1,240 / 3,400 - reports 12,345`. Speed up with a visible **×8** label if it runs long. Ends on `Synced in …. N new reports.` | "The app searches Gmail for messages from the Ingress sender with the Damage Report subject, and reads each one to extract the attacked portal's name and coordinates. Nothing else in the mailbox is read." |
| 7 | 2:40 | Open Google Drive in a new tab → open the spreadsheet the app created. Show the `reports` tab, then the `plots` tab. | "Results are written to a spreadsheet the app created in the user's own Drive. This is the only file the app can touch, which is what `drive.file` grants." |
| 8 | 3:10 | Back in the app. Click **Copy plots JSON** → `Copied 1,234 plots to clipboard.` | "The aggregated portal list is copied to the clipboard." |
| 9 | 3:25 | IITC intel map tab: open the plugin dialog, paste, submit. Heatmap renders over the map. | "Pasting it into our IITC map plugin renders the heatmap of attacked portals. This is what the whole flow exists to produce." |
| 10 | 4:00 | Open DevTools → Network, filter by domain. Point at the request list: only `googleapis.com`, `accounts.google.com`, and our own static origin. | "The app has no backend server. Every request goes directly from the browser to Google's APIs. Gmail messages and the data derived from them are never sent to, or stored on, any server we control." |
| 11 | 4:30 | Back on `/privacy.html`, Limited Use paragraph on screen. Hold 5 seconds. | "Damage Report Plots' use and transfer of information received from Google APIs to any other app will adhere to the Google API Services User Data Policy, including the Limited Use requirements." |

---

## Narration notes

The consent screen must be in English; the narration language is not specified.
English is safest — read the lines above, or add them as burned-in captions if
you would rather not record voice. Do not paraphrase the shot 11 line: it is the
Limited Use wording, and it must match
[`oauth-consent-verification.md`](./oauth-consent-verification.md) and
`/privacy.html` word for word.

## Before uploading

- [ ] Both consent screens are on screen long enough to read, and `gmail.readonly` is legible in shot 5
- [ ] The app name in the video matches the consent screen configuration exactly
- [ ] No personal mail content, other people's names, or unrelated tabs are visible
- [ ] The URL bar shows the prod domain throughout
- [ ] Uploaded as **unlisted** (not private — a private video is not viewable by the reviewer)

## Why submissions in this category come back

- The restricted scope's consent screen never appears, because the recording
  account had already granted it — the single most common cause, and the reason
  the revoke step is first on the setup list.
- The demo shows the app working but never shows the OAuth grant.
- The video shows a staging build on a domain that is not the verified one.
- Limited Use wording in the video, the privacy policy, and the submission form
  do not match.
