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

**Scopes**: `email profile https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/drive.file`. `drive.file` (non-sensitive)
replaces the sensitive `spreadsheets` scope and lets the app discover its **own**
single spreadsheet across devices via a Drive `appProperties` marker.

### apps/web sync engine (`apps/web/src/sync/`)

Server Ruby logic ported to TypeScript, run on the **main thread** (a Web Worker
can't be used — the HTML decoder needs `DOMParser` / `document.evaluate` XPath,
which don't exist in worker scope):

- `auth.ts` — GIS token-model auth (`loadGis`, `requestAccessToken`).
- `query.ts` — `buildQuery` (Gmail search query; 30-day windows, day-aligned).
- `gmail.ts` — batch `threads.get` body builder + multipart response parser.
- `engine.ts` — `runSync`: windowed scan, batch size 40 + 1s inter-batch sleep
  (avoids "Too many concurrent requests" 429), 429 backoff, 5000-thread cap with
  resume, 204 empty-window handling, `onWindow` callback for per-window append.
- `decoder.ts` — `EmailHtmlDecoder` port (native `DOMParser` + `document.evaluate`
  XPath). `truncateInternalDate` = 100-second day units (used for dedup + sheet).
- `record.ts` — `DamageReportRecord` + `deduplicate` (per-window is sufficient;
  a day belongs to one window) + `portalId` (SHA-256 → sqids, array-split).
- `drive.ts` / `sheets.ts` / `spreadsheet.ts` — Drive discovery (`appProperties`
  marker) + Sheets create/protect/append/get; `findOrCreateSpreadsheetId`.
- `resume.ts` — reads `lastReportTime` named range to resume the next scan.
- `mapping.ts` — `toReportRow` and `rowsToPlots` (→ `Plot[]` for the clipboard).
- `orchestrate.ts` — `runFullSync` (find/create → resume → scan → per-window
  append) and `readPlots` (read on Copy click, avoids QUERY recalc race).
- `http.ts` — `defaultFetch` wrapper (binds `globalThis.fetch`).

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
npm test
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

**Remaining**: prod cutover (set prod `VITE_GOOGLE_CLIENT_ID` + JS origin →
verify prod frontend → merge `develop`→`main` to tear down prod backend in one
apply, Terraform orders the destroy correctly) and Phase 5 production readiness
(brand verification only — **no CASA**: privacy policy, homepage, demo video,
per-scope justification; publish the consent screen).

**Caveat**: Terraform applies via ci-terraform on merge; changes to the CI role's
own IAM (`iam_cicd.tf`) need a **local targeted apply** (CI can't edit its own
policy).

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
- GitHub environments: `dev` / `prod`（apply用）、Secrets: `AWS_OIDC_ROLE_ARN`, `AWS_TERRAFORM_ROLE_ARN`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`、Repository secret: `MANAGEMENT_ACCOUNT_ID`、Variable: `VITE_GOOGLE_CLIENT_ID`（環境別）
- WIF attribute_condition: リポジトリ・environment・ref（develop/main またはPR）で制限済み

### Next Steps
- GuardDuty setup (later)
- SCP setup (later)
