# TradeMachineEx Development Guide

## Development Workflow

This application uses **shared infrastructure** with other TradeMachine microservices (Server, Client, etc).

### 🐳 Microservices Development Setup

**First-time setup:**

```bash
# 1. Start shared infrastructure (PostgreSQL, Redis) from parent directory
cd /path/to/TradeMachine  # Parent directory
docker-compose -f docker-compose.shared.yml up -d

# 2. Set up TradeMachineEx environment
cd TradeMachineEx
cp .env.development .env

# 3. (Optional) Customize your .env file with personal settings
# Note: .env is gitignored, so your changes stay local

# 4. Start TradeMachineEx app (connects to shared services)
docker-compose up
```

**Daily development:**

```bash
# Quick start (automated)
./start-dev.sh

# OR manual steps:
# 1. Ensure shared infrastructure is running
cd /path/to/TradeMachine && docker-compose -f docker-compose.shared.yml up -d

# 2. Start TradeMachineEx app
cd TradeMachineEx && docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down  # Stops only TradeMachineEx

# Run tests (locally)
./tests <file_name_optional>

# Run tests in docker (slower)
docker compose -f docker-compose.yml -f docker-compose.test.yml up --build
```

**Environment Variables:**
- **`.env.development`** → Committed template with safe defaults
- **`.env`** → Your personal copy (gitignored)
- **`docker-compose.yml`** → References `${VARIABLE}` from `.env`

**Microservices Architecture:**
- ✅ **Shared Infrastructure**: PostgreSQL + Redis used by all services
- ✅ **Service Isolation**: Each microservice has its own container
- ✅ **Network Communication**: Services communicate via Docker network
- ✅ **Version Parity**: Postgres 10 + Redis 5.0.7 match production
- ✅ **Resource Efficiency**: No duplicate infrastructure services

### 🔧 Alternative: Direct Machine Development

If you need to run directly on your machine:

```bash
# 1. Start dependencies only
docker-compose up postgres redis

# 2. Set environment variables (see .env.example)
export DATABASE_HOST=localhost
export DATABASE_PORT=5438  # Note: postgres runs on 5438 in docker-compose
export DATABASE_USER=trader_dev
export DATABASE_PASSWORD=caputo
# ... (see .env.example for complete list)

# 3. Run application
mix phx.server
```

### 🚀 Production Testing

Test the production build locally:

```bash
# Build and run production-like environment
docker-compose -f docker-compose.prod.yml up

# Note: Requires external database and proper environment variables
```

## Services & Architecture

### Shared Infrastructure (Parent `/docker-compose.shared.yml`)
| Service | Local Port | Container Port | Purpose | Version |
|---------|------------|----------------|---------|---------|
| PostgreSQL | 5438 | 5432 | Shared database | 10.23 (prod parity) |
| Redis | 6379 | 6379 | Shared job queues | 5.0.7 (prod parity) |
| Prometheus | 9091 | 9090 | Metrics collection | latest |
| Grafana | 3000 | 3000 | Metrics visualization | latest |

### TradeMachineEx Application (`/docker-compose.yml`)
| Service | Local Port | Container Port | Purpose |
|---------|------------|----------------|---------|
| TradeMachineEx | 4000 | 4000 | Phoenix application |
| Metrics | 9090 | 9090 | App-specific metrics |

**Network Communication:**
- **`trade_machine_shared`** network connects all services
- Apps connect to `postgres:5432` and `redis:6379` (Docker DNS)
- External access via localhost ports (5438, 6379, etc.)

## Configuration

All configuration follows 12-factor app principles:

- **Development**: Environment variables with defaults in `config/dev.exs`
- **Runtime**: Dynamic configuration in `config/runtime.exs`
- **Docker**: Environment variables defined in `docker-compose.yml`

See `.env.example` for all available environment variables.

## 🗄️ Database Migration Strategy

### **Prisma-Primary Architecture**

This Elixir application shares a PostgreSQL database with the TypeScript TradeMachineServer app. To avoid conflicts and ensure consistency, **Prisma (TypeScript) is the single source of truth for all database schema changes**.

### **🔧 How It Works**

**TypeScript App (TradeMachineServer):**
- ✅ Manages all database migrations via Prisma
- ✅ Creates, alters, and drops tables/columns
- ✅ Handles schema versioning and rollbacks
- ✅ Primary source of database structure

**Elixir App (TradeMachineEx):**
- ✅ Uses Ecto for data querying and insertion
- ✅ Keeps changeset functionality for data validation
- ❌ **Does NOT run migrations** (prevented via configuration)
- ❌ **Does NOT alter schema** (Mix tasks disabled)

### **⚙️ Configuration Changes Made**

**Removed from Migration Tasks:**
```elixir
# config/config.exs - Repo removed from ecto_repos to prevent Mix migration tasks
config :trade_machine, ecto_repos: []

# mix.exs - Migration aliases commented out to prevent accidental schema changes
# setup: ["deps.get", "ecto.setup"],  # Commented out
# "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
```

**What Still Works:**
- ✅ Database connections via `TradeMachine.Repo`
- ✅ Ecto queries, inserts, updates, deletes
- ✅ Changeset validation and data operations
- ✅ Schema definitions for the columns you need

### **🔍 Schema Validation**

A test suite validates that Ecto schemas match the actual database:

```bash
# Run schema validation tests
./test.sh test/schema_validation_test.exs

# This test will fail if:
# - A table referenced by Ecto no longer exists
# - A field in Ecto schema references a non-existent column
# - Field types are incompatible with database types
```

### **🛠️ Developer Workflow**

#### **When Database Schema Changes Are Needed:**

1. **Make changes in TypeScript app** (TradeMachineServer):
   ```bash
   cd ../TradeMachineServer
   # Edit prisma/schema.prisma
   npx prisma migrate dev --name descriptive_migration_name
   ```

2. **Update Elixir schemas** (if the change affects fields you use):
   ```elixir
   # Only update the fields your Elixir app actually uses
   # You don't need to map every database column
   defmodule TradeMachine.Data.User do
     typed_schema "user" do
       field :name, :string        # Map if you need it
       field :email, :string       # Map if you need it
       # field :last_login, :naive_datetime  # Don't map if you don't need it
     end
   end
   ```

3. **Validate schemas match database:**
   ```bash
   ./test.sh test/schema_validation_test.exs
   ```

#### **Adding New Tables/Models:**

1. **Create Prisma model first:**
   ```bash
   cd ../TradeMachineServer
   # Add model to prisma/schema.prisma
   npx prisma migrate dev --name add_new_table
   ```

2. **Create corresponding Ecto schema:**
   ```elixir
   # lib/trade_machine/data/my_new_model.ex
   defmodule TradeMachine.Data.MyNewModel do
     use TradeMachine.Schema

     typed_schema "my_new_table" do
       field :name, :string
       # Only map the fields you actually need in Elixir
       timestamps()
     end

     def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
       struct |> cast(params, [:name])
     end
   end
   ```

3. **Add to schema validation test:**
   ```elixir
   # test/schema_validation_test.exs
   @schemas [
     # ... existing schemas
     TradeMachine.Data.MyNewModel  # Add your new schema
   ]
   ```

### **🚨 Important Guidelines**

**DO:**
- ✅ Use Ecto for all data operations (queries, inserts, updates)
- ✅ Keep changeset functions for data validation
- ✅ Map only the database columns your Elixir app needs
- ✅ Run schema validation tests after Prisma migrations
- ✅ Update Ecto schemas when Prisma changes affect fields you use

**DON'T:**
- ❌ Run `mix ecto.migrate` or similar migration commands
- ❌ Create new migration files in `priv/repo/migrations/`
- ❌ Use Mix aliases that run migrations (`mix setup`, `mix ecto.setup`)
- ❌ Try to create/alter tables from Elixir

**If Schema Validation Fails:**
1. Check recent Prisma migrations for column changes
2. Update Ecto schema field names/types to match database
3. Remove Ecto fields that reference deleted columns
4. Add Ecto fields for new columns you want to access from Elixir

This approach ensures database consistency while allowing both applications to safely operate on the same data! 🎯

## 📊 Monitoring & Telemetry

### **How TradeMachineEx Monitoring Works**

This Elixir application uses **PromEx** library for comprehensive Phoenix and BEAM metrics that automatically integrate with the shared monitoring stack.

### **🚀 Enable Monitoring**

```bash
# Start shared infrastructure with monitoring
cd .. && ./start-infrastructure.sh
# Choose "y" for monitoring

# Start TradeMachineEx (metrics automatically enabled)
./start-dev.sh
```

**Access Points:**
- **Grafana**: http://localhost:3000 (see parent `.env` for credentials)
- **Prometheus**: http://localhost:9091 (raw metrics)
- **App Metrics Endpoint**: http://localhost:4000/metrics

### **🔍 What Metrics Are Emitted**

**Phoenix Web Metrics** (Automatic via PromEx)
```elixir
# HTTP request metrics
phoenix_http_request_duration_seconds
phoenix_http_requests_total
phoenix_controller_call_duration_seconds

# LiveView metrics (if using LiveView)
phoenix_live_view_mount_duration_seconds
phoenix_channel_join_duration_seconds
```

**BEAM VM Metrics** (Automatic via PromEx)
```elixir
# Memory and process metrics
beam_memory_total_bytes
beam_process_count
beam_scheduler_utilization_percent

# Garbage collection
beam_gc_duration_seconds_total
beam_gc_runs_total
```

**Database Metrics** (Automatic via PromEx + Ecto)
```elixir
# Database connection pool
ecto_db_query_duration_seconds
ecto_connection_pool_size
ecto_connection_pool_checked_out

# Query performance
ecto_repo_query_duration_seconds
```

**Custom Application Metrics** (Your business logic)
```elixir
# Examples of custom metrics you might add
trade_machine_jobs_processed_total
trade_machine_api_calls_duration_seconds
trade_machine_data_sync_errors_total
```

### **📈 Adding New Custom Metrics**

#### **1. Counter Metrics** (Things that increase)
```elixir
# In your application code
defmodule TradeMachineWeb.TradeController do
  use TradeMachineWeb, :controller

  # Define counter
  @trades_created_counter :telemetry.declare(
    [:trade_machine, :trades, :created],
    :counter,
    "Number of trades created"
  )

  def create(conn, params) do
    case TradeMachine.create_trade(params) do
      {:ok, trade} ->
        # Increment counter
        :telemetry.execute([:trade_machine, :trades, :created], %{count: 1}, %{
          user_id: trade.user_id,
          trade_type: trade.type
        })

        render(conn, "show.json", trade: trade)

      {:error, changeset} ->
        render(conn, "error.json", changeset: changeset)
    end
  end
end
```

#### **2. Duration Metrics** (How long things take)
```elixir
defmodule TradeMachine.DataSync do
  # Time long-running operations
  def sync_espn_data do
    :telemetry.span([:trade_machine, :espn_sync], %{}, fn ->
      result = fetch_and_process_espn_data()
      {result, %{status: :ok, records_processed: length(result)}}
    end)
  end

  defp fetch_and_process_espn_data do
    # Your sync logic here
  end
end
```

#### **3. Gauge Metrics** (Current values that go up/down)
```elixir
defmodule TradeMachine.MetricsReporter do
  use GenServer

  # Report current system state every 30 seconds
  def init(_) do
    :timer.send_interval(30_000, :report_metrics)
    {:ok, %{}}
  end

  def handle_info(:report_metrics, state) do
    # Report current active trades
    active_trades = TradeMachine.count_active_trades()
    :telemetry.execute([:trade_machine, :active_trades], %{count: active_trades})

    # Report queue sizes
    job_queue_size = get_job_queue_size()
    :telemetry.execute([:trade_machine, :job_queue_size], %{size: job_queue_size})

    {:noreply, state}
  end
end
```

### **🛠️ PromEx Configuration**

Your PromEx setup in `lib/trade_machine/application.ex`:

```elixir
# Add PromEx to your supervision tree
children = [
  # ... other children
  TradeMachine.PromEx
]
```

In `lib/trade_machine/prom_ex.ex`:
```elixir
defmodule TradeMachine.PromEx do
  use PromEx, otp_app: :trade_machine

  @impl true
  def plugins do
    [
      # Built-in Phoenix metrics
      PromEx.Plugins.Phoenix,
      PromEx.Plugins.Ecto,
      PromEx.Plugins.Oban,  # If using Oban for jobs
      PromEx.Plugins.BeamMetrics,

      # Your custom metrics
      TradeMachine.PromEx.CustomMetrics
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end
end
```

### **📊 Custom Metrics Plugin**

Create `lib/trade_machine/prom_ex/custom_metrics.ex`:
```elixir
defmodule TradeMachine.PromEx.CustomMetrics do
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :trade_machine_custom_metrics,
      [
        # Counter for trades created
        counter(
          [:trade_machine, :trades, :created],
          event_name: [:trade_machine, :trades, :created],
          description: "Total number of trades created",
          tags: [:user_id, :trade_type]
        ),

        # Histogram for ESPN sync duration
        distribution(
          [:trade_machine, :espn_sync, :duration],
          event_name: [:trade_machine, :espn_sync, :stop],
          description: "ESPN data sync duration",
          tags: [:status],
          unit: {:native, :millisecond}
        ),

        # Gauge for active trades
        last_value(
          [:trade_machine, :active_trades, :count],
          event_name: [:trade_machine, :active_trades],
          description: "Number of currently active trades"
        )
      ]
    )
  end
end
```

### **🔍 Viewing Your Metrics**

#### **In Grafana Dashboards:**
1. Go to http://localhost:3000
2. Navigate to TradeMachine folder
3. Your Elixir metrics appear alongside Node.js metrics
4. Create custom panels for your business metrics

#### **In Prometheus (Raw Queries):**
```promql
# HTTP request rate
rate(phoenix_http_requests_total[5m])

# Average response time
histogram_quantile(0.95, rate(phoenix_http_request_duration_seconds_bucket[5m]))

# Database connection pool usage
ecto_connection_pool_checked_out / ecto_connection_pool_size

# Your custom metrics
rate(trade_machine_trades_created_total[5m])
```

### **🚨 Monitoring Best Practices**

1. **Use Labels Wisely**: Add context but avoid high cardinality
   ```elixir
   # Good: Limited set of values
   :telemetry.execute([:trades, :created], %{count: 1}, %{type: "buy"})

   # Bad: Unlimited values (user IDs create too many unique metrics)
   :telemetry.execute([:trades, :created], %{count: 1}, %{user_id: user.id})
   ```

2. **Monitor What Matters**: Focus on business metrics and SLIs
   - Trade creation success/failure rates
   - Data sync job completion times
   - User activity patterns
   - System resource usage

3. **Set Up Alerts**: Use Grafana alerting for critical metrics
   - High error rates
   - Slow response times
   - Job failures
   - Database connection issues

### **🔧 Development Tips**

#### **Connecting to Running IEx Console**

When the app is running in Docker, connect to the live Elixir node for debugging:

```bash
# Connect to the running Elixir node in the container
docker exec -it trademachineex-app-1 sh -c 'iex --sname console --remsh trade_machine@$(hostname)'

# Test email functionality in the console:
# iex> user = %TradeMachine.Data.User{email: "test@example.com", display_name: "Test User", password_reset_token: "test123"}
# iex> TradeMachine.Mailer.PasswordResetEmail.send(user)
```

#### **Monitoring & Metrics**

```bash
# View metrics endpoint directly
curl http://localhost:4000/metrics

# Check telemetry events in IEx
iex> :telemetry.list_handlers([:trade_machine])

# Test custom metrics in development
iex> :telemetry.execute([:trade_machine, :test], %{value: 1})
```

This monitoring setup gives you **production-parity observability** for your Elixir application, automatically integrated with the shared TradeMachine monitoring stack! 🎯