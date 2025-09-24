# Docker Setup for TradeMachineEx

This document explains the Docker containerization implemented for TradeMachineEx.

## Quick Start

### Development
```bash
# Start all services (app, postgres, redis)
docker-compose up

# Start with monitoring stack
docker-compose --profile monitoring up

# View logs
docker-compose logs -f app
```

### Production
```bash
# Deploy to production
docker-compose -f docker-compose.prod.yml up -d

# View application logs
docker-compose -f docker-compose.prod.yml logs -f app
```

## What Was Implemented

### 1. Containerization
- **Multi-stage Dockerfile** with optimized build and runtime layers
- **Non-root user** for security
- **Health checks** for container orchestration
- **Signal handling** for graceful shutdowns

### 2. Enhanced Observability
- **Structured JSON logging** for better log parsing
- **PromEx integration** for Prometheus metrics
- **Custom business metrics** for Oban jobs and Google Sheets
- **Health endpoints** (`/health`, `/ready`, `/live`)
- **Metrics endpoint** on port 9090

### 3. Configuration Management
- **Environment-based configuration** via `runtime.exs`
- **Docker secrets** support for sensitive data
- **Container-optimized** BEAM VM settings

### 4. CI/CD Pipeline
- **GitHub Actions** workflow with Docker build/push
- **Security scanning** with Trivy
- **Multi-platform builds** (AMD64/ARM64)
- **Automated deployment** to DigitalOcean

## Environment Variables

### Required
- `DATABASE_PASSWORD` - PostgreSQL password
- `SECRET_KEY_BASE` - Phoenix secret (generate with `mix phx.gen.secret`)

### Optional
- `DATABASE_HOST` - Database hostname (default: localhost)
- `DATABASE_USER` - Database username (default: trader_dev)
- `DATABASE_NAME` - Database name (default: trade_machine)
- `DATABASE_SCHEMA` - Schema to use (default: staging)
- `PHX_HOST` - Phoenix host for URL generation
- `LOG_LEVEL` - Logging level (default: info)
- `GOOGLE_SHEETS_CREDS_PATH` - Path to Google Sheets credentials
- `GOOGLE_SPREADSHEET_ID` - Google Spreadsheet ID
- `ENABLE_CRON` - Enable scheduled jobs (default: false)

## Ports

- **4000** - Phoenix application
- **9090** - Prometheus metrics
- **5438** - PostgreSQL (development only)
- **6379** - Redis (development only)

## Observability Integration

### Prometheus Metrics
The application exposes metrics at `http://localhost:9090/metrics` including:
- Phoenix request metrics (duration, status codes)
- Database query metrics (timing, connection pool)
- Oban job processing metrics
- BEAM VM metrics (memory, processes)
- Custom Google Sheets integration metrics

### Structured Logging
Logs are output in JSON format with fields:
- `@timestamp` - ISO8601 timestamp
- `level` - Log level
- `message` - Log message
- `service` - Always "trade_machine_ex"
- `request_id` - Request correlation ID
- `oban_job_id` - Job ID for Oban jobs

### Grafana Alloy
Use the provided Alloy configuration to collect:
- Application metrics via Prometheus scraping
- Container logs via Docker log driver
- Structured log parsing and forwarding to Loki

## GitHub Secrets Required

For the CI/CD pipeline, configure these secrets in your GitHub repository:

- `DIGITALOCEAN_HOST` - Server hostname or IP
- `DIGITALOCEAN_USERNAME` - SSH username
- `DIGITALOCEAN_SSH_KEY` - SSH private key
- `DIGITALOCEAN_SSH_PORT` - SSH port (optional, defaults to 22)

## Production Deployment

1. **Set up environment variables** on your DigitalOcean server
2. **Create Docker secrets** for sensitive data:
   ```bash
   echo '{"your": "sheets_credentials"}' | docker secret create google_sheets_creds_v1 -
   ```
3. **Push to main branch** - GitHub Actions will automatically build and deploy

## Monitoring Setup

### Local Development
```bash
# Start with monitoring stack
docker-compose --profile monitoring up

# Access Grafana at http://localhost:3000 (admin/admin)
# Prometheus at http://localhost:9091
```

### Production
Configure Grafana Alloy to collect metrics and logs:
```bash
# Start Alloy with observability profile
docker-compose -f docker-compose.prod.yml --profile observability up -d
```

## Health Checks

- **`/health`** - Comprehensive health check (database, Oban, Google Sheets)
- **`/ready`** - Readiness probe (can serve requests?)
- **`/live`** - Liveness probe (is application responsive?)

## Troubleshooting

### Check application status
```bash
docker-compose ps
docker-compose logs app
```

### View metrics
```bash
curl http://localhost:9090/metrics
```

### Check health
```bash
curl http://localhost:4000/health
```

### Database connection issues
Ensure PostgreSQL is running and environment variables are correct:
```bash
docker-compose logs postgres
```

## Migration from Previous Deployment

The new Docker deployment replaces the previous tarball-based deployment. Key differences:

1. **No more manual tar extraction** - Docker handles deployment
2. **Environment variables** replace hardcoded configuration
3. **Health checks** enable better monitoring
4. **Structured logging** improves observability
5. **Automatic rollback** on deployment failure

The GitHub Actions workflow handles the migration automatically when you push to the main branch.