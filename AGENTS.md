# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a monorepo for "damage-report-plots-v2". The entire Gmail →
parse → Google Sheets pipeline runs **client-side in the browser** (React SPA);
there is **no application backend** — only static hosting (S3 + CloudFront) and
the Terraform/GCP scaffolding remain. The former Rails API + Sidekiq/SQS/Redis/ECS
pipeline was fully decommissioned (see "Client-Side Architecture" below).

The `apps/` directory contains independent applications:
- **`apps/web/`** — React 19 + Vite 8 + TypeScript SPA. Runs the whole pipeline:
  GIS auth → in-browser Gmail sync → write to the user's Google Sheet → copy the
  plots JSON to the clipboard.
- **`apps/iitc/`** — IITC userscript plugin. Pastes the plots JSON and renders the
  heatmap. Ingests via paste only (dialog in `apps/iitc/src/plugin.ts`,
  `parsePlots` in `apps/iitc/src/plots.ts`).

## Client-Side Architecture (CASA Avoidance)

**Why**: `gmail.readonly` is a Google *restricted* scope; serving external users
would normally require a CASA Tier 2 security assessment (paid, annual renewal).
Google exempts apps that never store or transmit restricted-scope data on a
server. Handling the whole flow in the browser keeps us exempt (only brand
verification is needed for production). Original PoC that proved feasibility:
`apps/poc/DESIGN.md` and `apps/poc/RESULTS.md` (GO verdict).

**Invariants** (breaking any one re-triggers CASA):
- Gmail access token / message bodies / derived data are **never** sent to,
  stored on, or logged by any server.
- OAuth uses the **GIS token model only** (PKCE, no client secret, no
  client-secret server exchange). ~1h token, no refresh token.
- `apps/web`'s clipboard output MUST stay the same `Plot[]` shape
  `{lat, lng, count, latest}` that `apps/iitc/src/plots.ts` expects.

**Scopes**: `profile https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/drive.file`. `drive.file` (non-sensitive)
replaces the sensitive `spreadsheets` scope and lets the app discover its **own**
single spreadsheet across devices via a Drive `appProperties` marker. `email` is
not requested — the UI shows a name and picture, both from `profile`.

`drive.file` stays even on the login token, which only reads: Drive has **no
read-only scope limited to the app's own files**. `drive.readonly` and
`drive.metadata.readonly` cover the user's whole Drive and are **restricted**,
so either would widen access *and* trigger CASA.

### apps/web sync engine (`apps/web/src/sync/`)

Server Ruby logic ported to TypeScript, run on the **main thread** (a Web Worker
can't be used — the HTML decoder needs `DOMParser` / `document.evaluate` XPath,
which don't exist in worker scope):

- `auth.ts` — GIS token-model auth (`loadGis`, `requestAccessToken`), plus
  `missingScopes` (the granular consent screen can withhold a scope and still
  issue a token, so a partial grant is rejected rather than cached) and
  `revokeAccessToken` (logout ends the grant; bounded because a blocked request
  leaves the GIS callback unfired). `LOGIN_SCOPE` / `SYNC_SCOPE` / `SHEET_SCOPE`
  are the three needs; `App.acquireToken` reuses one in-memory token whenever it
  *covers* the need, so Copy never fetches a third. `PROMPT_IF_NEEDED` (empty
  string) keeps the consent screen on first sign-in and first Gmail request only
  — login keeps the GIS default so accounts can still be switched.
- `query.ts` — `buildQuery` (Gmail search query; 30-day windows, day-aligned).
- `gmail.ts` — batch `threads.get` body builder + multipart response parser.
- `engine.ts` — `runSync`: windowed scan, quota-paced batches (see below),
  backoff on 429/403-quota (reported via `onRetry`, default `console.warn`),
  5000-thread cap with resume, 204 empty-window handling, `onWindow` callback
  for per-window append, `onProgress` fired per list page / per batch.
- `decoder.ts` — `EmailHtmlDecoder` port (native `DOMParser` + `document.evaluate`
  XPath). `truncateInternalDate` = 100-second day units (used for dedup + sheet).
- `record.ts` — `DamageReportRecord` + `deduplicate` (per-window) + `portalId`
  (SHA-256 → sqids, array-split).
- `drive.ts` / `sheets.ts` / `spreadsheet.ts` — Drive discovery (`appProperties`
  marker) + Sheets create/protect/append/get; `findOrCreateSpreadsheetId`.
- `resume.ts` — `readResumeSince` (`lastReportTime` named range, day-granular)
  plus the precise `stats!A7` pointer (`readSyncPointer`/`writeSyncPointer`),
  the raw `internalDate` high-water mark that stops the resume day being
  re-appended. `runFullSync` only ever advances it (forward-only).
- `mapping.ts` — `toReportRow` and `rowsToPlots` (→ `Plot[]` for the clipboard).
- `orchestrate.ts` — `runFullSync` (find/create → resume → scan → per-window
  append) and `readPlots` (read on Copy click, avoids QUERY recalc race).
- `http.ts` — `defaultFetch` wrapper (binds `globalThis.fetch`).

#### Gmail API rate limits (two separate limits)

Both are per user, and the constants live at the top of `engine.ts`:

- **Per-minute quota** — the dev GCP project is still on the pre-May-2026 set:
  `Previous quota: Units per minute per user` = **15,000**, `threads.get` = **10
  units** (the console usage graph is the only check; the old cost table is not
  published). `MIN_BATCH_INTERVAL_MS` is *derived* from `BATCH_SIZE ×
  THREADS_GET_UNITS` and the budget — never tune the two independently. The
  pacer holds batch *starts* that far apart and subtracts the request's own
  duration. Exceeding it returns **403** `Quota exceeded`, not 429.
- **Concurrency** — every sub-request of a batch runs at once, so `BATCH_SIZE`
  *is* the concurrency. 40 drew "Too many concurrent requests for user" 429s;
  **20** is clean. Lowering it is free: throughput is `BATCH_SIZE / interval`,
  which the derivation keeps constant (1,200 threads/min).

A batch's inner sub-responses carry their own status inside a **200** multipart
body, so rate limiting is invisible in the browser network panel —
`parseBatchResponse` reads the inner status and `onRetry` logs the backoff.

**Prod cutover**: the prod project has never called this API, so it may fall
under the post-May-2026 set instead (6,000 units/min, `threads.get` = 40) —
10× stricter. Check `Queries per minute per user` in the prod console.

## Development Commands

### apps/web
```bash
cd apps/web
npm install
npm run dev          # Vite dev server
npm run build        # production build (needs VITE_GOOGLE_CLIENT_ID)
npm test             # vitest (jsdom; supports document.evaluate XPath)
npm run test:watch
```
`VITE_GOOGLE_CLIENT_ID` selects the GIS OAuth client. In CI the deploy job
injects the per-environment value from the GitHub `vars.VITE_GOOGLE_CLIENT_ID`.

### apps/iitc
```bash
cd apps/iitc
npm install
npm run typecheck    # no test suite here; this and the build are what CI runs
npm run build        # produces the userscript
```

## Key Configuration Notes
- **No backend / no database**: the SPA talks to Google APIs directly.
- **Main branch**: `develop` (use this for pull requests). Never push directly.
- **Deploy**: `ci-web.yml` builds per-environment and deploys `apps/web` to S3 +
  CloudFront invalidation on push to `develop` (dev). Prod deploy needs a prod
  `VITE_GOOGLE_CLIENT_ID` var + the prod OAuth client's JS origin.

## Decommission history (Phase 3 — dev complete)

The server pipeline was removed in staged PRs (dev first; **prod is untouched
until prod cutover** because the shared module reconciles prod only on merge to
`main`):

- **Stage 1** — removed the ALB origin + `/api/*` `/auth/*` behaviors from the
  shared frontend CloudFront; scaled `web`/`worker` ECS to 0.
- **Stage 2** — deleted ECS services/cluster, ECR, ECS IAM, FireLens/log groups,
  and `ecspresso/`.
- **Stage 3** — deleted ALB/TG/listener/SG, ElastiCache + SG + VPC endpoint, SQS,
  Secrets, SSM params, WAF, ACM(api), API alarms.
- **Stage 4** — deleted `apps/api` (Rails app, omniauth/session/rack-attack,
  workers, Gmail/SQS e2e) and the `ci-api.yml` / `deploy-dev.yml` /
  `scale-dev.yml` / `decommission-ecs.yml` workflows.
- **Stage 5** — deleted the now-empty VPC/subnets/gateways/route tables. (No cost
  change: the IPv6-only design used a free egress-only IGW; there was no NAT.)
- **Follow-up** — pruned the now-dead backend permissions from the
  `github-actions-terraform` CI role (`iam_cicd.tf`, dev+prod); only ACM/S3/
  CloudFront/CloudTrail/tfstate grants remain.

**Prod status**: prod was **never fully deployed** — its state holds only the
bootstrap IAM role + tfstate access + GCP WIF (the current prod plan is
`16 to add, 2 to change, 0 to destroy`). So **prod cutover is a first-time
*creation* of the prod frontend, not a teardown.** It happens when
`develop`→`main` is merged and `apply-prod` runs — but because that apply creates
IAM policies on the CI's own role, the **first prod apply must be a local
bootstrap apply** (see Caveat), after which CI takes over.

**Step-by-step: [`docs/prod-cutover.md`](docs/prod-cutover.md)**. Two things
that runbook exists for: the first apply stops at CloudFront because the ACM
certificate is still `PENDING_VALIDATION` (there is no
`aws_acm_certificate_validation` resource, so it is a deliberate two-pass apply
with a DNS record in between), and `plots.world` is an **apex** domain, so the
alias record needs Route 53 or a provider with ALIAS/ANAME — a plain `CNAME` is
illegal there. Dev avoided both by living on `develop.plots.world`.

**Caveat**: Terraform applies via ci-terraform on merge; changes to the CI role's
own IAM (`iam_cicd.tf`) need a **local targeted apply** (CI can't edit its own
policy).

## Phase 5 — production readiness (OAuth verification, no CASA)

Publish the **prod** GCP OAuth consent screen (Testing → In production) and pass
Google's OAuth verification so external users can use the app without the
"unverified app" warning / 100-test-user cap.

**What actually needs verification**: only **`gmail.readonly`** (restricted).
`profile` (non-sensitive) and `drive.file` (non-sensitive, recommended)
don't drive verification. Client-side-only handling keeps us **exempt from the
CASA security assessment**; standard OAuth verification (brand + scope review +
demo video) still applies.

**Hard dependency**: the consent screen's homepage & privacy-policy URLs must be
live on the **verified prod domain**, and the prod OAuth client must exist — so
**prod cutover (above) must precede the verification submit.** Deliverables D1,
D2, D5, D6 can be produced in parallel now (recorded/written against dev).

**Deliverables** (owner):
- **D1 — Privacy policy page** (`/privacy` in `apps/web`): includes the **Limited
  Use disclosure** (compliance with the Google API Services User Data Policy;
  restricted data stays in the browser, is never sent to a server or shared).
  *Code — drafted in-repo.*
- **D2 — Homepage/landing**: extend the `HowItWorks` explainer with a clear app
  description, a screenshot, and a link to the privacy policy. *Code.*
- **D3 — Domain ownership verification**: verify the prod frontend domain in
  Google Search Console; add it to the consent screen's Authorized domains.
  *User (Google Console).*
- **D4 — Consent screen config (prod project)**: app name, logo, support email,
  developer contact, authorized domains, scopes, homepage + privacy URLs. *User;
  copy drafted in-repo.*
- **D5 — Per-scope justification**: English text explaining `gmail.readonly` is
  used only to parse "Ingress Damage Report" email bodies, plus Limited-Use and
  client-side-only statements. *Drafted in-repo.*
- **D6 — Demo video** (unlisted YouTube): the OAuth consent flow then the
  gmail.readonly usage (sync → Sheet → Copy → IITC), noting restricted data never
  leaves the browser. Shot list, narration and setup checklist in
  `docs/oauth-demo-video.md`. *User records, after prod cutover* — the consent
  screen must be the prod client on the verified domain. Note that incremental
  auth puts `gmail.readonly` on a **second** consent screen reached only by
  clicking Sync, and that the recording account's grant must be revoked first or
  neither screen appears.
- **D7 — Submit for verification** and set Publishing status to In production.
  *User (Google Console).*

**Sequence**: (1) build D1/D2/D5 + D6 storyboard now (one PR); (2) prod cutover;
(3) D3 domain verification; (4) record D6; (5) D4 → D7 submit; (6) answer
Google's review follow-ups.

**Notes**: restricted-scope review can take **weeks** with back-and-forth;
weak/absent **Limited Use** wording and demo-video gaps are the common rejection
reasons. The app remains usable during review (unverified warning + 100-user
cap); approval clears both.

## Infrastructure Setup Status

### AWS Organizations
- Management account, OU (`Workloads`), prod and dev member accounts are configured
- SCP: not yet configured

### IAM Identity Center
- Enabled in management account
- Identity source: Identity Center directory
- Permission sets: `AdministratorAccess`, `TerraformAccess`
- `TerraformAccess` is assigned to both prod and dev accounts
- Local AWS SSO profiles are configured for management, prod, and dev accounts

### Terraform State Backend (in management account)
- S3 bucket: `drp-tfstate` (us-west-2, versioning enabled, public access blocked)
- DynamoDB table: `drp-tfstate-lock` (us-west-2, for state locking)

### Terraform Configuration
- `terraform/environments/prod/` — AWS provider + Google provider (prod GCP project)
- `terraform/environments/dev/`  — AWS provider + Google provider (dev GCP project)
- The shared `terraform/modules/app_infra/` now provisions only the frontend
  (S3 + CloudFront + ACM) plus per-env GCP WIF, CloudTrail, and the CI IAM role.

#### Local terraform workflow
Backend (S3/DynamoDB) は management アカウントにあるため、init と apply で異なるプロファイルを使う:
```bash
# init: management プロファイルでバックエンドを指定
AWS_PROFILE=drp-mgmt terraform init -reconfigure -backend-config="profile=drp-mgmt"

# plan / apply: 対象環境のプロファイルを使用
AWS_PROFILE=drp-dev  terraform plan  -var="management_account_id=<MGMT_ACCOUNT_ID>"
AWS_PROFILE=drp-dev  terraform apply -var="management_account_id=<MGMT_ACCOUNT_ID>"
AWS_PROFILE=drp-prod terraform plan  -var="management_account_id=<MGMT_ACCOUNT_ID>"
AWS_PROFILE=drp-prod terraform apply -var="management_account_id=<MGMT_ACCOUNT_ID>"
```

### GCP
- Separate projects for prod and dev (already existed)
- Local authentication: Application Default Credentials (`gcloud auth application-default login`)
- Workload Identity Federation (WIF) configured in dev and prod GCP projects

### CI/CD (GitHub Actions)
- `.github/workflows/ci-terraform.yml` — PR時に plan、develop/main push 時に apply
- `.github/workflows/ci-web.yml` — apps/web の lint/test/build（PR）と dev への
  デプロイ（develop push）。`ci-iitc.yml` / `release-iitc.yml` は apps/iitc 用
- AWS: OIDC via management account `github-actions-terraform` role → cross-account AssumeRole to dev/prod
- GCP: Workload Identity Federation、`terraform-cicd` サービスアカウントに最小権限ロール付与
- GitHub environments: `dev` / `prod`（apply用）。仕分けの基準は「**認証情報か**」
  ではなく「**AWS アカウント ID を含むか**」— どれも識別子であってそれ単体では権限を
  与えないが、アカウント ID は偵察の手掛かりになるので伏せる:
  - **Environment secrets**: `AWS_OIDC_ROLE_ARN`, `AWS_TERRAFORM_ROLE_ARN`,
    `FRONTEND_BUCKET_NAME`（`…-frontend-<アカウントID>`）,
    `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`
  - **Environment variables**: `VITE_GOOGLE_CLIENT_ID`, `FRONTEND_DOMAIN_NAME`,
    `FRONTEND_CLOUDFRONT_DISTRIBUTION_ID`
  - **Repository secret**: `MANAGEMENT_ACCOUNT_ID`

  `FRONTEND_DOMAIN_NAME` を variable にしているのは公開値だからというだけでなく、
  secret だと terraform 側で `sensitive` にせざるを得ず、**ACM 検証用の DNS レコード
  （公開して当然のもの）が plan / output から読めなくなる**ため。同じ理由で
  `frontend_cloudfront_domain` と `frontend_acm_validation_records` の output も
  非 sensitive にしてある。`frontend_bucket_name` だけは sensitive のまま。
- WIF attribute_condition: リポジトリ・environment・ref（develop/main またはPR）で制限済み

### Next Steps
- GuardDuty setup (later)
- SCP setup (later)
