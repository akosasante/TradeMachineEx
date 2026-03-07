# Production Dockerfile for TradeMachineEx
# Build stage: compile the application
FROM hexpm/elixir:1.18.0-erlang-27.1.2-alpine-3.20.3 AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base

# Set production environment
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Copy dependency files
COPY mix.exs mix.lock ./

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install production dependencies only
RUN mix deps.get --only prod

# Copy source code
COPY assets/ ./assets/
COPY priv/ ./priv/
COPY config/ ./config/
COPY lib/ ./lib/

# Build assets and compile application
RUN mix assets.deploy && \
    mix compile

# Build the release
RUN mix release

# Runtime stage: use same exact alpine version as builder to ensure OpenSSL compatibility
FROM alpine:3.20.3 AS runtime

# Install runtime dependencies (no version pinning needed with matching base)
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    bash \
    curl

# Create non-root user for security
RUN addgroup -g 1000 -S trademachine && \
    adduser -u 1000 -S trademachine -G trademachine

# Create directories for logs and credentials
RUN mkdir -p /var/log/trade_machine_ex && \
    chown -R trademachine:trademachine /var/log/trade_machine_ex

# Set working directory
WORKDIR /app

# Copy the release from builder stage
COPY --from=builder --chown=trademachine:trademachine /app/_build/prod/rel/trade_machine ./

# Switch to non-root user
USER trademachine

# Environment variables for container
ENV MIX_ENV=prod
ENV HOME=/app
ENV CONTAINER_MODE=true

# Expose ports
# Phoenix application (4000 default, 4001 in prod)
EXPOSE 4000 4001

# Health check (port is configurable via PORT env var in production)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT:-4000}/health || exit 1

# Default command
CMD ["bin/trade_machine", "start"]