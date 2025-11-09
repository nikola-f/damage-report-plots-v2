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
- **Session middleware**: Added ActionDispatch::Cookies and ActionDispatch::Session::CookieStore for OmniAuth support (apps/api/config/application.rb:45-46)
- **CORS**: Enabled and configured to support cross-origin requests (apps/api/config/initializers/cors.rb)
- **Authentication**: Google OAuth2 + JWT-based stateless authentication
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

# Run with documentation format (already configured in .rspec)
bundle exec rspec

# Database commands (if/when added)
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
bin/rails db:reset

# Generate new resources
bin/rails generate controller ControllerName
bin/rails generate model ModelName

# Routes
bin/rails routes
```

## Authentication & Authorization

### Google OAuth2 + JWT Authentication
The API uses a stateless JWT-based authentication system with Google OAuth2 for sign-in.

**Key Components:**
- **JWT Service**: `lib/json_web_token.rb` - Handles JWT encoding/decoding
- **Authenticatable Concern**: `app/controllers/concerns/authenticatable.rb` - JWT validation middleware
- **Sessions Controller**: `app/controllers/sessions_controller.rb` - OAuth callback and token management
- **OmniAuth Configuration**: `config/initializers/omniauth.rb` - Google OAuth2 provider setup

**Token Types:**
- **Access Token**: Short-lived (15 minutes), used for API requests
- **Refresh Token**: Long-lived (7 days), used to obtain new access tokens

**Authentication Endpoints:**
```
POST   /auth/google_oauth2              - Initiate Google OAuth flow
GET    /auth/google_oauth2/callback     - OAuth callback (returns JWT + Google tokens)
POST   /auth/refresh                    - Refresh access token
DELETE /auth/logout                     - Logout (client-side token deletion)
GET    /auth/failure                    - OAuth failure handler
```

**Protected Endpoints:**
```
GET    /api/v1/profile                  - Example protected endpoint (requires JWT)
```

**Using Protected Endpoints:**
Include the JWT access token in the Authorization header:
```
Authorization: Bearer <access_token>
```

**Token Flow:**
1. Client initiates OAuth via `POST /auth/google_oauth2`
2. User authenticates with Google
3. Google redirects to `/auth/google_oauth2/callback`
4. API returns: JWT access token, refresh token, user info, and Google OAuth tokens
5. Client stores tokens securely
6. Client includes JWT in `Authorization` header for protected endpoints
7. When access token expires, use refresh token via `POST /auth/refresh`

## Key Configuration Notes

- **No database**: The Rails app currently has no database layer configured (Active Record is disabled)
- **Health check endpoint**: `/up` endpoint available at apps/api/config/routes.rb:6
- **CORS Configuration**: Configured via `ALLOWED_ORIGINS` environment variable (defaults to `http://localhost:3000`)
- **Encrypted credentials**: Uses Rails encrypted credentials (apps/api/config/credentials.yml.enc with master.key)
- **Main branch**: `develop` (use this for pull requests)

### Required Credentials (Encrypted)
Edit credentials with: `EDITOR=nano bin/rails credentials:edit`

Required structure:
```yaml
jwt_secret_key: <SecureRandom.hex(64)>
jwt_refresh_secret: <SecureRandom.hex(64)>
google:
  client_id: your_google_client_id
  client_secret: your_google_client_secret
```

### Required Environment Variables
```bash
ALLOWED_ORIGINS=http://localhost:3000,https://yourfrontend.com
```

### Dependencies
**Authentication & Security:**
- `jwt` - JSON Web Token encoding/decoding
- `omniauth-google-oauth2` - Google OAuth2 authentication
- `omniauth-rails_csrf_protection` - CSRF protection for OmniAuth
- `rack-cors` - Cross-Origin Resource Sharing support

**Testing:**
- `rspec-rails` - RSpec testing framework for Rails
- `rspec-request_describer` - Automatic request spec descriptions

## Creating Protected API Endpoints

To create a new protected endpoint that requires JWT authentication:

1. **Create a controller** in `app/controllers/api/v1/`:
```ruby
module Api
  module V1
    class YourController < ApplicationController
      include Authenticatable  # Require JWT authentication

      def index
        # Access current user via helpers
        user_id = current_user_id
        user_email = current_user_email
        user_name = current_user_name

        render json: { data: 'your data' }
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
  before do
    allow(Rails.application.credentials).to receive(:jwt_secret_key!).and_return('test_secret_key')
  end

  context 'with valid JWT token' do
    let(:payload) { { sub: '12345', email: 'test@example.com', name: 'Test User' } }
    let(:token) { JsonWebToken.encode(payload) }

    it 'returns data' do
      get '/api/v1/your_resource', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:ok)
    end
  end
end
```

## Test Coverage

Current test suite: **24 tests, 100% passing**

**Test files:**
- `spec/lib/json_web_token_spec.rb` - JWT service tests (11 tests)
- `spec/requests/api/v1/profile_spec.rb` - Protected endpoint tests (4 tests)
- `spec/requests/sessions_spec.rb` - Authentication flow tests (7 tests)
- `spec/requests/health_spec.rb` - Health check tests (2 tests)
