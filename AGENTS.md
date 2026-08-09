# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a monorepo project for "damage-report-plots-v2" with a Rails API-only backend. The project is structured with an `apps/` directory containing individual applications.

> **Note**: The project is migrating to a fully client-side architecture to avoid
> a CASA security assessment. The server-based pipeline documented below is being
> replaced — see "Client-Side Migration" next. Existing architecture docs remain
> valid until each phase's decommission step lands.

## Client-Side Migration (In Progress — CASA Avoidance)

**Why**: `gmail.readonly` is a Google *restricted* scope; serving external users
would normally require a CASA Tier 2 security assessment (paid, annual renewal).
Google exempts apps that never store or transmit restricted-scope data on a
server. A PoC (`apps/poc/`, **GO verdict**) proved the whole Gmail
fetch → parse → Sheets-write flow runs entirely in the browser. Full rationale,
measurements, and design: `apps/poc/DESIGN.md` and `apps/poc/RESULTS.md`.

**Target delivery form** (decided):
- **`apps/web`** absorbs the entire pipeline: GIS **token-model** auth
  (PKCE, no client secret) → in-browser Gmail sync (`threads.list` + batch
  `threads.get`) → HTML parse → dedupe/aggregate → write to the user's **own**
  Google Sheet → **copy the plots JSON to the clipboard**.
- **`apps/iitc` is unchanged.** It already ingests via paste (see the dialog in
  `apps/iitc/src/plugin.ts` and `parsePlots` in `apps/iitc/src/plots.ts`).
  **Hard constraint**: apps/web's clipboard output MUST stay the same `Plot[]`
  shape `{lat, lng, count, latest}` that `apps/iitc/src/plots.ts` expects.
- No Gmail data ever reaches a server → CASA not required (only brand
  verification for production).

**Invariants** (breaking any one re-triggers CASA):
- Gmail access token / message bodies / derived data are never sent to, stored
  on, or logged by the backend.
- OAuth uses the GIS token model only (no client-secret server exchange).

**Phased plan**:
0. Create a **Web-application** OAuth client for GIS; register JS origins; enable
   Gmail API + Google Sheets API.
1. Port server logic to TypeScript in `apps/web`: `DamageReportQuery`,
   `GmailClient` (list + batch get), `EmailHtmlDecoder` (DOMParser +
   `document.evaluate` XPath), `DamageReportRecord` + dedupe/aggregate,
   `SpreadsheetsClient` (create/protect/append/get). Windowed scan with resume,
   429 backoff, silent token re-acquisition. Runs on the **main thread** — a Web
   Worker can't be used because the HTML decoder needs DOMParser/document.evaluate,
   which don't exist in worker scope.
2. Rework `apps/web` UI: replace omniauth/session login with GIS; the sync button
   drives the in-browser pipeline with progress; "Copy plots JSON" is sourced
   from in-browser/Sheet data (format unchanged).
3. Parallel run: validate client-side output has parity with the current backend;
   run an at-scale full-history scan check.
4. **Staged** backend decommission: remove Sidekiq workers, SQS, Redis/Valkey,
   and related ECS services (Terraform/ecspresso); slim or remove the Rails API
   (keep static hosting for apps/web); drop omniauth/session/rack-attack-auth and
   the Gmail/SQS e2e specs.
5. Production readiness (brand verification only, **no CASA**): privacy policy,
   homepage, demo video, per-scope justification; publish the consent screen.

**Status**: Phase 1 complete — merged to `develop` (PR #349) and running in **dev**
(GIS login → in-browser Gmail sync → Drive spreadsheet → Copy → IITC verified
end-to-end). Now in **Phase 3 (backend decommission)**. Prod is not cut over yet
(needs prod `VITE_GOOGLE_CLIENT_ID` + JS origin), so the prod backend stays until
prod cutover / Phase 5.

### Backend decommission (Phase 3, staged)

Decommission the server pipeline now that the SPA talks to Google directly. Do
**dev first, prod later** (after prod cutover). Each stage is a small PR; keep the
frontend healthy throughout.

- **Stage 1 — API traffic cutover (reversible)**: remove the ALB origin and
  `/api/*` `/auth/*` behaviors from the frontend CloudFront (`frontend.tf`) — the
  distribution is **shared**, so keep the S3 origin/default behavior; scale the
  `web`/`worker` ECS services to `desiredCount: 0` (ecspresso). Observe dev.
- **Stage 2 — delete ECS compute**: `ecspresso delete` web/worker; remove ECS
  cluster, ECR, ECS task/exec IAM, FireLens/log groups; delete `ecspresso/`.
- **Stage 3 — delete API-support infra** (Terraform): ALB/TG/listener/SG,
  ElastiCache (Valkey) + SG + VPC endpoint, SQS, Secrets (rails_master_key,
  google_client_id/secret, redis_url), SSM params, WAF, ACM (api), API alarms.
  **Order**: CloudFront must lose its ALB reference (Stage 1) before the ALB is
  deleted here.
- **Stage 4 — CI/CD & app**: delete `ci-api.yml`, `deploy-dev.yml`, `scale-dev.yml`;
  remove `apps/api` (Rails app, omniauth/session/rack-attack, workers, Gmail/SQS
  e2e). Update this doc.
- **Stage 5 — network teardown (optional, last)**: if the VPC has no tenants left,
  remove VPC/subnets/NAT/IGW (drops the NAT fixed cost).

**Caveats**: Terraform applies via ci-terraform on merge; changes to the CI role's
own IAM (`iam_cicd.tf`) need a **local targeted apply** (CI can't edit its own
policy). Redis-held tokens/spreadsheet_ids are discarded — fine, the client uses
Drive discovery for fresh sheets.

## Architecture

### Monorepo Structure
- `apps/api/` - Rails 8.0.3 API-only application (Ruby 3.4.4)
- Each app in `apps/` is independent and has its own configuration

### Rails API Application (`apps/api/`)
- **API-only mode**: No views, helpers, or assets. Configured with minimal middleware suitable for API apps (apps/api/config/application.rb:42)
- **Framework selection**: Only loads essential Rails components:
  - Active Model (no Active Record - database-free)
  - Action Controller
  - Action View
  - RSpec (Rails Test Unit disabled)
  - Excludes: Active Job, Active Record, Active Storage, Action Mailer, Action Mailbox, Action Text, Action Cable
- **Session middleware**: Added ActionDispatch::Cookies and ActionDispatch::Session::CookieStore (apps/api/config/application.rb:45-46)
- **CORS**: Enabled and configured to support cross-origin requests (apps/api/config/initializers/cors.rb)
- **Authentication**: Google OAuth2 via OmniAuth + Rails session cookie
- **Ruby version**: 3.4.4
- **Unit test**: Based on t-wada's TDD, using RSpec for Rails with rspec-request_describer

## Development Commands

### Rails API (`apps/api/`)
All commands should be run from the `apps/api/` directory:

```bash
cd apps/api

# Install dependencies
bundle install

# Start the development server
bin/rails server
# or
bin/dev

# Run console
bin/rails console

# Run tests (e2e specs under spec/e2e are excluded by default — see below)
bundle exec rspec

# Run specific spec file
bundle exec rspec spec/path/to/spec_file.rb

# Run specific test by line number
bundle exec rspec spec/path/to/spec_file.rb:line_number

# Routes
bin/rails routes
```

### End-to-end (e2e) specs

`spec/e2e/**` drive real external services (Gmail/Sheets APIs, SQS via LocalStack
or AWS, and Valkey), so they do **not** run in a bare local checkout. They are
**excluded from `bundle exec rspec` by default** and run only when opted in:

- **CI**: the dedicated `e2e` job in `.github/workflows/ci-api.yml` runs on push
  to `develop`. It provisions LocalStack + Valkey services and secrets and sets
  `RUN_E2E=true`.
- **Local (optional)**: start the required services/env (documented in each
  `spec/e2e/*_spec.rb` header) and run with `RUN_E2E=true bundle exec rspec spec/e2e`.

The exclusion is enforced in `spec/spec_helper.rb`: files under `spec/e2e` are
tagged `:e2e` and filtered out unless `RUN_E2E=true`. A plain local run stays
hermetic; CI opts in explicitly.

## Authentication & Authorization

### Google OAuth2 + Session Cookie

The API uses Google OAuth2 (via OmniAuth) for sign-in. After a successful OAuth callback, a Rails session cookie is issued. All protected endpoints check for `session[:user_id]`.

**Key Components:**
- **Authenticatable Concern**: `app/controllers/concerns/authenticatable.rb` - checks `session[:user_id]` before each action
- **Sessions Controller**: `app/controllers/sessions_controller.rb` - OAuth callback and scope grant endpoints
- **OmniAuth Configuration**: `config/initializers/omniauth.rb` - Google OAuth2 provider setup with dynamic scope support

**Session contents:**
```
session[:user_id]  - Google account ID
session[:email]
session[:name]
session[:picture]
```

### Incremental OAuth Scope Acquisition

Google API access is granted in three levels. Each level adds scopes to the existing grant (`include_granted_scopes: true`).

| Level | Scope | When |
|-------|-------|------|
| 1 | `email profile` | Login |
| 2 | + `spreadsheets.readonly` | Before reading existing spreadsheet |
| 3 | + `gmail.readonly spreadsheets` | Before triggering sync |

Scope constants are defined in `SessionsController`:
- `LOGIN_SCOPE`
- `SPREADSHEETS_SCOPE`
- `SYNC_SCOPE`

**Endpoints:**
```
POST   /auth/google_oauth2              - Initiate Google OAuth flow (Level 1)
GET    /auth/google_oauth2/callback     - OAuth callback (login or scope upgrade)
DELETE /auth/logout                     - Logout (clears session)
GET    /auth/failure                    - OAuth failure handler

POST   /auth/grant/spreadsheets         - Store Level 2 scope in session, return authorization_url
POST   /auth/grant/sync                 - Store Level 3 scope in session, return authorization_url
```

**Scope upgrade flow:**
1. Client calls `POST /auth/grant/spreadsheets` or `POST /auth/grant/sync` (requires active session)
2. Server stores desired scope in session, responds with `{ authorization_url: "/auth/google_oauth2" }`
3. Client navigates to the authorization URL
4. OmniAuth reads scope from session and redirects to Google with the new scope
5. Google redirects to `/auth/google_oauth2/callback`
6. Callback updates the stored access token in Redis and responds with `{ granted_scope: "..." }`

**Protected Endpoints:**
```
GET    /api/v1/profile                  - Returns current user info
POST   /api/v1/sync                     - Triggers Gmail sync (requires Level 3 scope)
```

**Using Protected Endpoints:**
Protected endpoints require an active session cookie. No Authorization header is used.

### Redis Stores (`lib/user_store.rb`)

Google access tokens and spreadsheet IDs are stored in Redis, keyed by Google account ID (`user_id`).

```ruby
UserStore.access_token.store(user_id, token)   # TTL: 3600s (matches Google token lifetime)
UserStore.access_token.fetch(user_id)

UserStore.spreadsheet_id.store(user_id, id)    # no TTL
UserStore.spreadsheet_id.fetch(user_id)        # raises KeyError if not found
```

`UserStore::USER_ID_ATTR` is the SQS message attribute name used to pass `user_id` between workers.

## Key Configuration Notes

- **No database**: The Rails app currently has no database layer configured (Active Record is disabled)
- **Health check endpoint**: `/up` endpoint available at apps/api/config/routes.rb
- **CORS Configuration**: Configured via `ALLOWED_ORIGINS` environment variable (defaults to `http://localhost:3000`)
- **Encrypted credentials**: Uses Rails encrypted credentials (apps/api/config/credentials.yml.enc with master.key)
- **Main branch**: `develop` (use this for pull requests)

### Required Environment Variables
```bash
ALLOWED_ORIGINS=http://localhost:3000,https://yourfrontend.com
GOOGLE_CLIENT_ID=your_google_client_id         # read by config/initializers/omniauth.rb
GOOGLE_CLIENT_SECRET=your_google_client_secret # (in ECS both are injected from Secrets Manager)
```

### Dependencies
**Authentication & External Services:**
- `omniauth-google-oauth2` - Google OAuth2 authentication
- `omniauth-rails_csrf_protection` - CSRF protection for OmniAuth
- `rack-cors` - Cross-Origin Resource Sharing support
- `rack-attack` - Per-client-IP rate limiting (global + `/auth/*`; keys on the CloudFront-appended X-Forwarded-For entry)
- `redis` - Access token and spreadsheet ID store
- `aws-sdk-sqs` - Inter-worker messaging
- `sidekiq` - Background job processing

**Testing:**
- `rspec-rails` - RSpec testing framework for Rails
- `rspec-request_describer` - Automatic request spec descriptions

## Creating Protected API Endpoints

To create a new protected endpoint that requires an active session:

1. **Create a controller** in `app/controllers/api/v1/`:
```ruby
module Api
  module V1
    class YourController < ApplicationController
      include Authenticatable

      def index
        render json: { data: 'your data', user_id: current_user_id }
      end
    end
  end
end
```

2. **Add routes** in `config/routes.rb`:
```ruby
namespace :api do
  namespace :v1 do
    resources :your_resource, only: [:index, :show, :create]
  end
end
```

3. **Write tests** in `spec/requests/api/v1/`:
```ruby
require 'rails_helper'

RSpec.describe "GET /api/v1/your_resource", type: :request do
  context 'with active session' do
    before { login_as }

    it 'returns data' do
      get '/api/v1/your_resource'

      expect(response).to have_http_status(:ok)
    end
  end

  context 'without session' do
    it 'returns unauthorized' do
      get '/api/v1/your_resource'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

## Worker Pipeline

Background jobs process Gmail threads and write results to Google Sheets:

```
POST /api/v1/sync
  └─ GmailThreadListWorker (Sidekiq)
       └─ sqs_report_queue (SQS FIFO)
            └─ GmailThreadBatchWorker (polls SQS)
                 └─ sqs_portal_queue (SQS FIFO)
                      └─ SpreadsheetSyncWorker (polls SQS)
                           └─ Google Sheets API
```

Each SQS message carries `user_id` as a message attribute (`UserStore::USER_ID_ATTR`) so workers can fetch the correct access token and spreadsheet ID from Redis.

## Test Coverage

Unit/request/service/worker specs run by default with `bundle exec rspec`
(e2e excluded — see "End-to-end (e2e) specs" above). The e2e suite runs
separately in CI / with `RUN_E2E=true`.

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
- Both environments initialized and applied

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
- AWS: OIDC via management account `github-actions-terraform` role → cross-account AssumeRole to dev/prod
- GCP: Workload Identity Federation、`terraform-cicd` サービスアカウントに最小権限ロール付与
- GitHub environments: `dev` / `prod`（apply用）、Secrets: `AWS_OIDC_ROLE_ARN`, `AWS_TERRAFORM_ROLE_ARN`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`、Repository secret: `MANAGEMENT_ACCOUNT_ID`
- WIF attribute_condition: リポジトリ・environment・ref（develop/main またはPR）で制限済み

### Next Steps
- GuardDuty setup (later)
- SCP setup (later)
