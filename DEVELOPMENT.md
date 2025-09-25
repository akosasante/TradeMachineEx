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

## Monitoring (Optional)

Enable full monitoring stack:

```bash
# Start with monitoring services
docker-compose --profile monitoring up
```

This adds:
- **Prometheus** (http://localhost:9091) - Metrics collection
- **Grafana** (http://localhost:3000) - Dashboards (admin/admin)