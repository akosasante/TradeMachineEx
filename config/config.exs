# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure timezone database for proper timezone support
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :trade_machine,
  # Elixir app uses Ecto for data operations only -
  ## no migration management. Prisma (TypeScript) handles all schema changes
  ecto_repos: [TradeMachine.Repo.Production, TradeMachine.Repo.Staging]

# Draft picks season thresholds.
# Sorted descending: the first entry whose date is <= today's UTC date is used.
# If today precedes all thresholds, the job raises a RuntimeError.
# Update this list each year once the MLB season start date is confirmed.
config :trade_machine,
  draft_picks_season_thresholds: [
    {~D[2027-04-01], 2027},
    {~D[2026-03-25], 2026},
    {~D[2025-03-27], 2025}
  ]

# Configures the endpoint
config :trade_machine,
       TradeMachineWeb.Endpoint,
       url: [
         host: "localhost"
       ],
       secret_key_base: "Z7REctlbORv2zBbr6+J/uAhh2uzB9/pvnVciY9FGv4BEku0i4u8uL67H+TjjdQwe",
       render_errors: [
         view: TradeMachineWeb.ErrorView,
         accepts: ~w(html json),
         layout: false
       ],
       pubsub_server: TradeMachine.PubSub,
       live_view: [
         signing_salt: "wKce98o8"
       ]

# Configures Elixir's Logger
config :logger,
       :console,
       format: "$time $metadata[$level] $message\n",
       metadata: [
         :request_id,
         :email_type,
         :data,
         :user_id,
         :error,
         :job_id,
         :queue,
         :worker,
         :span_name,
         :job_args_keys,
         :result,
         :args
       ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.12.18",
  default: [
    args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => Path.expand("../deps", __DIR__)
    }
  ]

# Configure Oban for job processing
# Note: Oban uses Production repo for job persistence
config :trade_machine, Oban,
  repo: TradeMachine.Repo.Production,
  plugins: [
    {Oban.Plugins.Pruner, max_age: div(:timer.hours(48), 1_000)},
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", TradeMachine.Jobs.MinorsSync},
       {"22 7 * * *", TradeMachine.Jobs.EspnTeamSync},
       {"32 7 * * *", TradeMachine.Jobs.EspnMlbPlayersSync}
     ]}
  ],
  queues: [minors_sync: 1, draft_sync: 1, emails: 2, espn_sync: 1, discord: 1]

# Emailing
config :swoosh,
  api_client: Swoosh.ApiClient.Finch

config :trade_machine, TradeMachine.Mailer,
  adapter: Swoosh.Adapters.Local,
  from_email: "trademachine@flexfoxfantasy.com",
  from_name: "Flex Fox Fantasy TradeMachine"

# OpenTelemetry configuration
# Get version from mix project
app_version = Mix.Project.config()[:version]

config :opentelemetry,
  service_name: "trademachine-elixir",
  service_version: app_version

config :opentelemetry, :resource,
  service: %{
    name: "trademachine-elixir",
    version: app_version
  },
  deployment: %{
    environment: Mix.env()
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
