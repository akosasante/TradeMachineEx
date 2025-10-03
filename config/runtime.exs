import Config

# Runtime configuration for containerized deployment
# This configuration is evaluated at runtime and allows for
# environment-based configuration in Docker containers

# Database configuration
config :trade_machine, TradeMachine.Repo,
  username: System.get_env("DATABASE_USER") || "trader_dev",
  password: System.fetch_env!("DATABASE_PASSWORD"),
  database: System.get_env("DATABASE_NAME") || "trade_machine",
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"),
  pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE") || "10"),
  show_sensitive_data_on_connection_error: false,
  after_connect:
    {Postgrex, :query!,
     ["SET search_path TO #{System.get_env("DATABASE_SCHEMA", "staging")}", []]}

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
  server: true

# Google Sheets credentials configuration
# In containers, this should point to a mounted secret or env var
sheets_creds_path = System.get_env("GOOGLE_SHEETS_CREDS_PATH") || "./sheet_creds.json"

config :trade_machine,
  sheets_creds_filepath: sheets_creds_path,
  spreadsheet_id: System.get_env("GOOGLE_SPREADSHEET_ID")

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
oban_plugins =
  if System.get_env("DATABASE_SCHEMA") == "staging" or System.get_env("ENABLE_CRON") == "true" do
    [
      {Oban.Plugins.Pruner, max_age: div(:timer.hours(48), 1_000)},
      {Oban.Plugins.Cron,
       crontab: [
         {"0 2 * * *", TradeMachine.Jobs.MinorsSync}
       ]}
    ]
  else
    [
      {Oban.Plugins.Pruner, max_age: div(:timer.hours(48), 1_000)}
    ]
  end

config :trade_machine, Oban,
  repo: TradeMachine.Repo,
  plugins: oban_plugins,
  queues: [
    minors_sync: String.to_integer(System.get_env("OBAN_MINORS_SYNC_CONCURRENCY") || "1"),
    draft_sync: String.to_integer(System.get_env("OBAN_DRAFT_SYNC_CONCURRENCY") || "1")
  ],
  prefix: System.get_env("DATABASE_SCHEMA", "staging")

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

# OpenTelemetry configuration - using working approach with custom processor config
config :opentelemetry,
  span_processor: :batch,
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
