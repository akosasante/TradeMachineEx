# Multi-stage Dockerfile for TradeMachineEx
# Build stage: compile the application
FROM hexpm/elixir:1.12.3-erlang-24.0.6-alpine-3.14.2 AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base \
    nodejs \
    npm

# Set build-time environment
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Copy dependency files
COPY mix.exs mix.lock ./

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies
RUN mix deps.get --only prod

# Copy assets and build them
COPY assets/ ./assets/
COPY priv/ ./priv/
COPY config/ ./config/
COPY lib/ ./lib/

# Install Node.js dependencies and build assets
WORKDIR /app/assets
RUN npm install
WORKDIR /app

# Build assets and compile application
RUN mix assets.deploy && \
    mix compile

# Build the release
RUN mix release

# Runtime stage: minimal image with only the release
FROM alpine:3.14.2 AS runtime

# Install runtime dependencies
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
# 4000: Phoenix application
# 9090: Prometheus metrics endpoint
EXPOSE 4000 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Default command
CMD ["bin/trade_machine", "start"]