use Mix.Config

# Production configuration for containerized deployment
# Most configuration is now handled in runtime.exs for better container support

# Phoenix Endpoint - basic configuration
# Runtime configuration handles dynamic values
config :trade_machine, TradeMachineWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

# Import runtime configuration which handles environment-based settings
# This allows for proper containerized deployment with environment variables

# Note: prod.secret.exs is not imported in containerized deployments
# All secrets and environment-specific configuration is handled in runtime.exs
