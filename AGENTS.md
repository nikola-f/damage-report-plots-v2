# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a monorepo project for "damage-report-plots-v2" with a Rails API-only backend. The project is structured with an `apps/` directory containing individual applications.

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

# Run tests
bundle exec rspec

# Run specific spec file
bundle exec rspec spec/path/to/spec_file.rb

# Run specific test by line number
bundle exec rspec spec/path/to/spec_file.rb:line_number

# Routes
bin/rails routes
```

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

### Required Credentials (Encrypted)
Edit credentials with: `EDITOR=nano bin/rails credentials:edit`

Required structure:
```yaml
google:
  client_id: your_google_client_id
  client_secret: your_google_client_secret
```

### Required Environment Variables
```bash
ALLOWED_ORIGINS=http://localhost:3000,https://yourfrontend.com
```

### Dependencies
**Authentication & External Services:**
- `omniauth-google-oauth2` - Google OAuth2 authentication
- `omniauth-rails_csrf_protection` - CSRF protection for OmniAuth
- `rack-cors` - Cross-Origin Resource Sharing support
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

Current test suite: **196 examples, 0 failures**

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
