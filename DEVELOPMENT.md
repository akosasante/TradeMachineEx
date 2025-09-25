# TradeMachineEx Development Guide

## Development Workflow

This application is designed for **containerized development** using Docker Compose.

### 🐳 Recommended: Containerized Development

Start the full development environment:

```bash
# Start all services (PostgreSQL, Redis, App with hot reloading)
docker-compose up

# Or run in background
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop services
docker-compose down
```

**Benefits:**
- ✅ Complete isolated environment
- ✅ All dependencies (PostgreSQL, Redis) included
- ✅ Hot reloading enabled (code changes reflected immediately)
- ✅ No local service conflicts
- ✅ Consistent across team members

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