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
- **CORS**: rack-cors gem included but not configured (apps/api/config/initializers/cors.rb is commented out)
- **Ruby version**: 3.4.4
- **Unit test**: Based on t-wada's TDD, using RSpec for Rails

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

## Key Configuration Notes

- **No database**: The Rails app currently has no database layer configured (Active Record is disabled)
- **Health check endpoint**: `/up` endpoint available at apps/api/config/routes.rb:6
- **Encrypted credentials**: Uses Rails encrypted credentials (apps/api/config/credentials.yml.enc with master.key)
- **Main branch**: `develop` (use this for pull requests)
