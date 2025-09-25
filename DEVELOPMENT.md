# TradeMachineEx Development Guide

## Development Workflow

This application is designed for **containerized development** using Docker Compose.

### 🐳 Recommended: Containerized Development

**First-time setup:**

```bash
# 1. Copy development environment template
cp .env.development .env

# 2. (Optional) Customize your .env file with personal settings
# Note: .env is gitignored, so your changes stay local

# 3. Start all services (PostgreSQL, Redis, App with hot reloading)
docker-compose up
```

**Daily development:**

```bash
# Start services in background
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down
```

**Environment Variables:**
- **`.env.development`** → Committed template with safe defaults
- **`.env`** → Your personal copy (gitignored)
- **`docker-compose.yml`** → References `${VARIABLE}` from `.env`

**Benefits:**
- ✅ Complete isolated environment
- ✅ All dependencies (PostgreSQL, Redis) included
- ✅ Hot reloading enabled (code changes reflected immediately)
- ✅ No secrets in git
- ✅ Personal customization without git conflicts

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

## Services

| Service | Local Port | Container Port | Purpose |
|---------|------------|----------------|---------|
| App | 4000 | 4000 | Phoenix application |
| PostgreSQL | 5438 | 5432 | Database |
| Redis | 6379 | 6379 | Job queues (Oban) |
| Metrics | 9090 | 9090 | Prometheus metrics |
| Prometheus | 9091 | 9090 | Metrics collection (optional) |
| Grafana | 3000 | 3000 | Metrics visualization (optional) |

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