import Config

# Runtime configuration for containerized deployment
# This configuration is evaluated at runtime and allows for
# environment-based configuration in Docker containers

# Database configuration - Dual Repo Pattern
prod_schema = System.get_env("PROD_SCHEMA") || "public"
staging_schema = System.get_env("STAGING_SCHEMA") || "staging"
# Only configure if DATABASE_PASSWORD is set (allows running without DB for testing)
if System.get_env("DATABASE_PASSWORD") do
  # Production database configuration
  config :trade_machine, TradeMachine.Repo.Production,
    username:
      System.get_env("PROD_DATABASE_USER") || System.get_env("DATABASE_USER") || "trader_dev",
    password: System.fetch_env!("DATABASE_PASSWORD"),
    database: System.get_env("DATABASE_NAME") || "trade_machine",
    hostname:
      System.get_env("PROD_DATABASE_HOST") || System.get_env("DATABASE_HOST") || "localhost",
    port: String.to_integer(System.get_env("PROD_DATABASE_PORT") || "5432"),
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10"),
    show_sensitive_data_on_connection_error: false,
    socket_options: [keepalive: true],
    after_connect: {Postgrex, :query!, ["SET search_path TO #{prod_schema}", []]},
    migration_default_prefix: "#{prod_schema}",
    priv: "priv/repo"

  # Staging database configuration
  config :trade_machine, TradeMachine.Repo.Staging,
    username:
      System.get_env("STAGING_DATABASE_USER") || System.get_env("DATABASE_USER") || "trader_dev",
    password: System.fetch_env!("DATABASE_PASSWORD"),
    database: System.get_env("DATABASE_NAME") || "trade_machine",
    hostname:
      System.get_env("STAGING_DATABASE_HOST") || System.get_env("DATABASE_HOST") || "localhost",
    port: String.to_integer(System.get_env("STAGING_DATABASE_PORT") || "5432"),
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10"),
    show_sensitive_data_on_connection_error: false,
    socket_options: [keepalive: true],
    after_connect: {Postgrex, :query!, ["SET search_path TO #{staging_schema}", []]},
    migration_default_prefix: staging_schema,
    priv: "priv/repo"
end

# Phoenix Endpoint configuration
config :trade_machine, TradeMachineWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "4000")
  ],
  url: [
    host: System.get_env("PHX_HOST") || "localhost",
    port: String.to_integer(System.get_env("PORT") || "4000")
  ],
  secret_key_base:
    if(config_env() == :prod,
      do: System.fetch_env!("SECRET_KEY_BASE"),
      else: "eSr80uBsxpy9nSvPKgFaLtPz+SMFDXa54wB4+IKMEcGUtFmVeaHpFYkpHXhX5GlN"
    ),
  server: config_env() != :test

# Minor league sheet configuration (public CSV export via Req)
if config_env() != :test do
  config :trade_machine,
    minor_league_sheet_id: System.fetch_env!("MINOR_LEAGUE_SHEET_ID"),
    minor_league_sheet_gid: System.get_env("MINOR_LEAGUE_SHEET_GID") || "806978055"
end

# Draft picks sheet configuration (public CSV export via Req)
if config_env() != :test do
  config :trade_machine,
    draft_picks_sheet_id: System.fetch_env!("DRAFT_PICKS_SHEET_ID"),
    draft_picks_sheet_gid: System.get_env("DRAFT_PICKS_SHEET_GID") || "142978697"
end

# Logger configuration for structured logging in containers
if config_env() == :prod do
  # Configure structured JSON logging for better parsing by Loki
  config :logger,
    backends: [:console],
    utc_log: true,
    handle_otp_reports: true,
    level: String.to_existing_atom(System.get_env("LOG_LEVEL") || "info")

  config :logger, :console,
    format: {LogFormatter, :format},
    metadata: [
      :request_id,
      :user_id,
      :mfa,
      :file,
      :line,
      :email_type,
      :data,
      :error,
      :job_id,
      :queue,
      :worker
    ]
else
  # Development logging with unified formatter
  config :logger,
    backends: [:console],
    level: :debug

  config :logger, :console,
    format: {LogFormatter, :format},
    metadata: [
      :request_id,
      :user_id,
      :mfa,
      :file,
      :line,
      :email_type,
      :data,
      :error,
      :job_id,
      :queue,
      :worker
    ]
end

# Oban configuration with environment-based settings
# Skip Oban runtime config in test mode - test.exs handles it
if config_env() != :test do
  prod_oban_plugins =
    if System.get_env("ENABLE_CRON") == "true" do
      [
        {Oban.Plugins.Pruner, max_age: div(:timer.hours(48), 1_000)},
        Oban.Plugins.Lifeline,
        {Oban.Plugins.Cron,
         crontab: [
           {"0 2 * * *", TradeMachine.Jobs.MinorsSync},
           {"22 7 * * *", TradeMachine.Jobs.EspnTeamSync},
           {"32 7 * * *", TradeMachine.Jobs.EspnMlbPlayersSync},
           {"0 3 * * *", TradeMachine.Jobs.DraftPicksSync}
         ]}
      ]
    else
      [
        {Oban.Plugins.Pruner, max_age: div(:timer.hours(48), 1_000)},
        Oban.Plugins.Lifeline
      ]
    end

  # Production Oban instance - handles all job types including cron jobs
  config :trade_machine, Oban.Production,
    name: Oban.Production,
    repo: TradeMachine.Repo.Production,
    plugins: prod_oban_plugins,
    queues: [
      minors_sync: String.to_integer(System.get_env("OBAN_MINORS_SYNC_CONCURRENCY") || "1"),
      draft_sync: String.to_integer(System.get_env("OBAN_DRAFT_SYNC_CONCURRENCY") || "1"),
      emails: 2,
      espn_sync: 1,
      discord: 1
    ],
    prefix: prod_schema

  # Staging Oban instance - only handles email jobs, no cron jobs
  config :trade_machine, Oban.Staging,
    name: Oban.Staging,
    repo: TradeMachine.Repo.Staging,
    plugins: [
      {Oban.Plugins.Pruner, max_age: div(:timer.hours(48), 1_000)},
      Oban.Plugins.Lifeline
    ],
    queues: [
      emails: 2,
      discord: 1
    ],
    prefix: staging_schema
end

# PromEx (Prometheus metrics) configuration
if config_env() == :test do
  config :trade_machine, TradeMachine.PromEx, disabled: true
else
  config :trade_machine, TradeMachine.PromEx,
    disabled: false,
    manual_metrics_start_delay: :no_delay,
    drop_metrics_groups: [],
    grafana: [
      host: System.get_env("GRAFANA_HOST"),
      auth_token: System.get_env("GRAFANA_TOKEN"),
      annotate_app_lifecycle: true,
      upload_dashboards_on_start: false,
      folder_name: "TradeMachine"
    ]
end

# Emailing
if config_env() == :prod do
  config :trade_machine, TradeMachine.Mailer,
    adapter: Swoosh.Adapters.Brevo,
    api_key: System.fetch_env!("BREVO_API_KEY"),
    finch_name: Swoosh.Finch,
    from_email: "tradebot@flexfoxfantasy.com",
    from_name: "FlexFox Fantasy TradeMachine"
else
  config :trade_machine, TradeMachine.Mailer,
    from_email: "tradebot@flexfoxfantasy.com",
    from_name: "FlexFox Fantasy TradeMachine"
end

# CSS inlining for emails
config :premailex, :html_parser, Premailex.HTMLParser.Floki

# Application-specific configuration
config :trade_machine,
  upload_grafana_dashboards_on_start: config_env() == :dev

if config_env() != :prod do
  config :trade_machine,
    frontend_url_production: "http://localhost:3031",
    frontend_url_staging: "http://localhost:3031",
    staging_email: "test_staging@example.com"
else
  config :trade_machine,
    frontend_url_production: System.fetch_env!("FRONTEND_URL"),
    frontend_url_staging: System.fetch_env!("STAGING_FRONTEND_URL"),
    staging_email: System.fetch_env!("STAGING_EMAIL")
end

# OpenTelemetry runtime configuration - using official documented format
otlp_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://localhost:4318"

# OpenTelemetry configuration - using processors config for full control
config :opentelemetry,
  #  span_processor: :batch,
  traces_exporter: :otlp

# Custom batch processor configuration to ensure faster exports for debugging
config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {:opentelemetry_exporter, :otlp_traces},
    config: %{
      # Export every 1 second for debugging
      scheduled_delay_ms: 1_000,
      max_queue_size: 2048,
      export_timeout_ms: 30_000,
      max_export_batch_size: 512
    }
  }

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: otlp_endpoint

# Optional: Configure trace sampling
if System.get_env("OTEL_TRACES_SAMPLER") == "traceidratio" do
  sampling_ratio =
    case System.get_env("OTEL_TRACES_SAMPLER_ARG") do
      # Default 10% sampling
      nil -> 0.1
      arg -> String.to_float(arg)
    end

  config :opentelemetry, :sampler, {:trace_id_ratio_based, sampling_ratio}
end

# Add OpenTelemetry resource attributes from environment
# Get application version at runtime
app_version = Application.spec(:trade_machine, :vsn) |> to_string()

# Standard OpenTelemetry resource attributes
resource_attributes = %{
  service: %{
    name: System.get_env("OTEL_SERVICE_NAME") || "trademachine-elixir",
    version: System.get_env("OTEL_SERVICE_VERSION") || app_version
  },
  deployment: %{
    environment: Atom.to_string(config_env())
  }
}

config :opentelemetry, :resource, resource_attributes

# ESPN Fantasy API configuration
config :trade_machine,
  espn_cookie: System.get_env("ESPN_COOKIE"),
  espn_swid: System.get_env("ESPN_SWID"),
  espn_league_id: System.get_env("ESPN_LEAGUE_ID") || "545",
  espn_season_year:
    (case System.get_env("ESPN_SEASON_YEAR") do
       nil -> Date.utc_today().year
       year_str -> String.to_integer(year_str)
     end)

# Discord/Nostrum configuration
# Only configure if DISCORD_BOT_TOKEN is set and not in test environment
if config_env() != :test do
  if discord_token = System.get_env("DISCORD_BOT_TOKEN") do
    config :nostrum,
      token: discord_token,
      # Gateway intents - minimal for now, add more when needed
      gateway_intents: [
        :guilds,
        :guild_messages
      ]
  end
end
