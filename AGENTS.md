# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and other AI agent tools when working with code in this repository.

## Project Overview

TradeMachineEx is an Elixir Phoenix application that serves as the job processing and background task service for the TradeMachine fantasy baseball trading platform. It complements the main TypeScript server by handling scheduled operations, data imports, and concurrent processing that benefit from Elixir's actor model and fault tolerance.

## Development Commands

### Setup and Development
- **Install dependencies**: `mix deps.get`
- **Start development server (recommended)**: `./start-dev.sh --skip-infrastructure`
- **Start development server (local)**: `mix phx.server`
- **Start with infrastructure**: `./start-dev.sh` (starts PostgreSQL and Redis containers)
- **iex REPL in running container**: `./console.sh` or `./console.sh <name>` (to provide a custom name for the node) eg: `./console.sh myrepl`

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
- `Oban` - Job queue processor for background and cron jobs
- `PromEx.DashboardUploader` - Grafana dashboard management (optional)

**Directory Structure**:
- `lib/trade_machine/data/` - Ecto schemas and data models
- `lib/trade_machine/discord/` - Discord integration (trade announcements)
- `lib/trade_machine/jobs/` - Background job processors
- `lib/trade_machine/mailer/` - Email templates and delivery
- `lib/trade_machine/minor_leagues/` - Minor league sheet sync (fetch, parse, sync)
- `lib/trade_machine_web/` - Phoenix web layer

### Discord Trade Announcements
- **Library**: Nostrum for Discord API integration
- **Module Structure**: `announcer.ex` (public API), `formatter.ex` (pure formatting), `embed_builder.ex` (embed construction), `client.ex` (API wrapper)
- **Format**: Condensed embed (Option 2) with CSV names, `[Level - MLB Team - Position]` suffix
- **Uphold Time**: 11 PM Eastern, minimum 24 hours from trade submission
- **Usage**: `TradeMachine.Discord.Announcer.announce_trade("trade-id", :production)`
- **Testing**: `TradeMachine.Discord.EmbedTester` for format experiments with sample data
- **See**: `DISCORD_IMPLEMENTATION.md` for full documentation

### Email System
- **Provider**: Brevo (SendInBlue) via Swoosh adapter
- **Templates**: Phoenix.Swoosh with HTML/text templates in `lib/trade_machine/mailer/templates/`
- **CSS Inlining**: Premailex for email-compatible styling
- **Layout Structure**: Separate layout and email views with stadium background image

### Data Processing
- **Minor League Sync**: Fetches public Google Sheet as CSV via `Req`, parses the multi-team layout, and syncs player ownership to the database
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
- Uses Oban for all background and scheduled jobs
- Jobs should handle failures gracefully with retry logic
- Use structured logging for monitoring
- All sync jobs use `SyncTracking` to record execution metadata to the DB and `TraceContext` for OpenTelemetry distributed tracing

## Important Notes

### Database Management
- **NEVER run `mix ecto.migrate`** for application tables - all schema changes handled by Prisma in TypeScript server
- Database connection shares the same PostgreSQL instance as TradeMachineServer
- Use only `mix deps.get` for setup, not database-modifying commands

#### Exception: Oban Infrastructure Tables
The **ONLY** exception to the no-migrations rule is for Oban's internal tables:
- `oban_jobs`, `oban_peers`, and other Oban-managed tables
- These are **not** part of your application domain model
- Already marked with `@@ignore` in Prisma schema
- Required for background job processing and cron jobs

**When to run Oban migrations:**
- Initial deployment setup
- After upgrading Oban to a new version
- If you see errors about missing `oban_peers` table

**How to run Oban migrations in production:**
```bash
# Migrate both Production and Staging databases
docker exec -it trade_machine_ex_app /app/bin/trade_machine eval "TradeMachine.Release.migrate_all()"

# Or migrate individual repos
docker exec -it trade_machine_ex_app /app/bin/trade_machine eval "TradeMachine.Release.migrate(TradeMachine.Repo.Production)"
docker exec -it trade_machine_ex_app /app/bin/trade_machine eval "TradeMachine.Release.migrate(TradeMachine.Repo.Staging)"
```

**⚠️ Critical:** Only run migrations for Oban tables. Application tables (users, teams, trades, etc.) are still managed exclusively by Prisma migrations in the TypeScript server.

### Docker Development
- Uses `docker-compose.yml` for the application container
- Shared infrastructure via `../docker-compose.shared.yml` in parent directory
- Development containers connect to shared services (PostgreSQL on 5438, Redis on 6379)

### Testing Environment
- Tests use `.env.test` environment sourced by `test.sh` script
- Test database should be separate from development database
- Use `./test.sh` script rather than `mix test` directly for proper environment setup

---

## Oban Jobs Reference

Quick-reference for the job system. All jobs live in `lib/trade_machine/jobs/`. For detailed per-job documentation (data flows, step-by-step descriptions, architecture diagram), see [docs/job-system.md](docs/job-system.md).

### Repos and Oban Instances

There are two PostgreSQL repos and two Oban instances, one per environment:

| Repo | DB Schema | Oban Instance | Queues |
|---|---|---|---|
| `TradeMachine.Repo.Production` | `public` (or `$PROD_SCHEMA`) | `Oban.Production` | `minors_sync`, `espn_sync`, `draft_sync`, `emails` |
| `TradeMachine.Repo.Staging` | `staging` (or `$STAGING_SCHEMA`) | `Oban.Staging` | `emails` only |

Cron jobs always run against **Production** only. The Staging Oban instance only processes emails enqueued by the TypeScript server when `APP_ENV=staging`.

---

### Scheduled (Cron) Jobs

Cron is enabled in production when `DATABASE_SCHEMA=staging` or `ENABLE_CRON=true`. Schedules are in UTC.

| Job | Module | Cron (production) | Queue | Max Attempts |
|---|---|---|---|---|
| Minor League Sync | `TradeMachine.Jobs.MinorsSync` | `0 2 * * *` (2:00 AM) | `minors_sync` | 5 |
| ESPN Team Sync | `TradeMachine.Jobs.EspnTeamSync` | `22 7 * * *` (7:22 AM) | `espn_sync` | 3 |
| ESPN MLB Players Sync | `TradeMachine.Jobs.EspnMlbPlayersSync` | `32 7 * * *` (7:32 AM) | `espn_sync` | 3 |

> **Dev note:** In `dev.exs`, MinorsSync runs every 2 minutes (`*/2 * * * *`) for easy testing. In `config.exs` (the base config), it runs every 5 minutes and all three jobs are scheduled.

---

### On-Demand Jobs

Enqueued by the TypeScript server (`TradeMachineServer`) via direct Prisma inserts into the `oban_jobs` table.

| Job | Module | Queue | Max Attempts | Enqueued by |
|---|---|---|---|---|
| Email Worker | `TradeMachine.Jobs.EmailWorker` | `emails` | 3 | `TradeMachineServer/src/DAO/v2/ObanDAO.ts` |

---

### Job Details

#### `MinorsSync` — `lib/trade_machine/jobs/minors_sync.ex`

Syncs minor league player ownership from a public Google Sheet to both databases.\
**Env vars:** `MINOR_LEAGUE_SHEET_ID`, `MINOR_LEAGUE_SHEET_GID` (default `"806978055"`)\
**Concurrency guard:** `SyncLock` (`:minors_sync`) prevents overlapping runs\
**Unique constraint:** Only one job allowed in `available/scheduled/executing/retryable` states at a time

---

#### `EspnTeamSync` — `lib/trade_machine/jobs/espn_team_sync.ex`

Syncs ESPN fantasy team metadata (`team.espnTeam` JSON column) to both databases. Runs 10 minutes before `EspnMlbPlayersSync` so team data is fresh. Uses `ESPN_SEASON_YEAR` env var.

---

#### `EspnMlbPlayersSync` — `lib/trade_machine/jobs/espn_mlb_players_sync.ex`

Syncs the full ESPN major league player pool to both databases via paginated API fetch and multi-phase matching engine.\
**Env vars:** `ESPN_SEASON_YEAR`\
**Concurrency guard:** `SyncLock` (`:mlb_players_sync`) prevents overlapping runs\
**Unique constraint:** Only one job allowed in `available/scheduled/executing/retryable` states at a time

---

#### `EmailWorker` — `lib/trade_machine/jobs/email_worker.ex`

Sends transactional emails. Enqueued by the TypeScript server when a user registers or requests a password reset. Selects repo based on `env` arg (`"production"` → Production repo, anything else → Staging).

**Supported email types:**

| `email_type` arg | Email sent |
|---|---|
| `"reset_password"` | Password reset link |
| `"registration"` or `"registration_email"` | Welcome / registration confirmation |
| `"test"` | Test email (dev use) |

> `"registration_email"` is the value sent by `ObanDAO.ts` in TradeMachineServer; `"registration"` is accepted as an alias for forward compatibility.

**Enqueue args:** `{ "email_type": "...", "data": "<userId>", "env": "production"|"staging" }`

> **How jobs get enqueued:** The TypeScript server (`ObanDAO.ts`) inserts rows directly into the `oban_jobs` table via Prisma. The Elixir app picks them up from the `emails` queue. The `env` field tells the worker which database to use so the correct user record is found.

---

### Shared Job Infrastructure

| Module | Purpose |
|---|---|
| `TradeMachine.SyncLock` | In-memory lock to prevent concurrent runs of the same sync job |
| `TradeMachine.SyncTracking` | Writes job execution metadata (start, complete, fail) to `SyncJobExecution` table |
| `TradeMachine.Tracing.TraceContext` | OpenTelemetry span management; propagates trace context from TypeScript server |
| `Oban.Plugins.Pruner` | Cleans up completed/discarded jobs after 48 hours (production) |
| `Oban.Plugins.Lifeline` | Rescues orphaned jobs that were executing when the node crashed |
