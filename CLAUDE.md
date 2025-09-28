# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TradeMachineEx is an Elixir Phoenix application that serves as the job processing and background task service for the TradeMachine fantasy baseball trading platform. It complements the main TypeScript server by handling scheduled operations, data imports, and concurrent processing that benefit from Elixir's actor model and fault tolerance.

## Development Commands

### Setup and Development
- **Install dependencies**: `mix deps.get`
- **Start development server (recommended)**: `./start-dev.sh --skip-infrastructure`
- **Start development server (local)**: `mix phx.server`
- **Start with infrastructure**: `./start-dev.sh` (starts PostgreSQL and Redis containers)

### Testing
- **Run all tests**: `./test.sh`
- **Run specific test file**: `./test.sh test/schema_validation_test.exs`
- **Run tests in Docker**: `docker compose -f docker-compose.yml -f docker-compose.test.yml up --build`

### Code Quality
- **Lint**: `mix credo`
- **Type check**: `mix dialyzer`

### Other Commands
- **Format code**: `mix format`
- **Run setup**: `mix setup` (only installs deps, no DB changes)

## Architecture

### Shared Infrastructure Pattern
TradeMachineEx operates as a microservice that connects to **shared infrastructure** with the main TypeScript server:
- **PostgreSQL**: Port 5438 (shared database, schema managed by Prisma in TypeScript server)
- **Redis**: Port 6379 (shared for job queues and caching)
- **Application**: Port 4000 (TradeMachineEx Phoenix server)

### Database Schema Approach
- **Schema Management**: All database migrations handled by Prisma in the TypeScript server (`../TradeMachineServer`)
- **Field Mapping**: Uses custom `@field_source_mapper` to convert Elixir `snake_case` fields to `camelCase` database columns for compatibility
- **Schema Definition**: Uses `typed_ecto_schema` for type safety with `TradeMachine.Schema` base module
- **Primary Keys**: UUID primary keys with `Ecto.UUID` type
- **Timestamps**: Maps to `dateCreated`/`dateModified` database columns

### Key Components

**Application Supervision Tree**:
- `TradeMachine.Repo` - Ecto repository connecting to shared PostgreSQL
- `TradeMachineWeb.Telemetry` - Metrics and monitoring
- `Phoenix.PubSub` - Message passing (currently unused)
- `Oban` - Job queue processor (commented out but available)
- `Goth` - Google Sheets OAuth integration (optional)
- `PromEx.DashboardUploader` - Grafana dashboard management (optional)

**Directory Structure**:
- `lib/trade_machine/data/` - Ecto schemas and data models
- `lib/trade_machine/jobs/` - Background job processors
- `lib/trade_machine/mailer/` - Email templates and delivery
- `lib/trade_machine/sheet_reader/` - Google Sheets integration
- `lib/trade_machine_web/` - Phoenix web layer

### Email System
- **Provider**: Brevo (SendInBlue) via Swoosh adapter
- **Templates**: Phoenix.Swoosh with HTML/text templates in `lib/trade_machine/mailer/templates/`
- **CSS Inlining**: Premailex for email-compatible styling
- **Layout Structure**: Separate layout and email views with stadium background image

### Data Processing
- **Google Sheets**: Optional integration for importing Excel data via Google Sheets API
- **Concurrent Jobs**: Designed to leverage Elixir's concurrency for data processing tasks
- **Type Safety**: Uses `typed_ecto_schema` for compile-time type checking

## Configuration

### Environment Files
- `.env.development` - Development template (copy to `.env`)
- `.env.test` - Test environment (sourced by `test.sh`)
- `.env.example` - Environment variable documentation

### Config Files
- `config/config.exs` - Base configuration
- `config/dev.exs` - Development settings
- `config/prod.exs` - Production settings
- `config/runtime.exs` - Runtime configuration (database, email, etc.)
- `config/test.exs` - Test environment settings

## Development Patterns

### Schema Definition
Use `TradeMachine.Schema` as base for all data models:
```elixir
defmodule TradeMachine.Data.User do
  use TradeMachine.Schema

  typed_schema "user" do
    field(:display_name, :string, null: false)
    # Fields automatically map snake_case to camelCase in database
  end
end
```

### Email Development
- Templates in `lib/trade_machine/mailer/templates/`
- Use `TradeMachine.Mailer` with `__using__` macro for shared functionality
- HTML templates use `.heex` extension, text templates use `.eex`
- Stadium background image embedded as base64 in layout

### Job Processing
- Designed for Oban integration (currently disabled)
- Jobs should handle failures gracefully with retry logic
- Use structured logging for monitoring

## Important Notes

### Database Management
- **NEVER run `mix ecto.migrate`** - all schema changes handled by Prisma in TypeScript server
- Database connection shares the same PostgreSQL instance as TradeMachineServer
- Use only `mix deps.get` for setup, not database-modifying commands

### Docker Development
- Uses `docker-compose.yml` for the application container
- Shared infrastructure via `../docker-compose.shared.yml` in parent directory
- Development containers connect to shared services (PostgreSQL on 5438, Redis on 6379)

### Testing Environment
- Tests use `.env.test` environment sourced by `test.sh` script
- Test database should be separate from development database
- Use `./test.sh` script rather than `mix test` directly for proper environment setup