import Config

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure your database - Dual Repo Pattern
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.

# Production repo for testing
config :trade_machine, TradeMachine.Repo.Production,
  username: System.get_env("DATABASE_USER", "trader_test"),
  password: System.get_env("DATABASE_PASSWORD", "caputo"),
  database: System.get_env("DATABASE_NAME", "trade_machine"),
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("PROD_DATABASE_PORT", "5432")),
  show_sensitive_data_on_connection_error: true,
  pool: Ecto.Adapters.SQL.Sandbox,
  after_connect: {Postgrex, :query!, ["SET search_path TO test", []]},
  priv: "priv/repo/production"

# Staging repo for testing
config :trade_machine, TradeMachine.Repo.Staging,
  username: System.get_env("DATABASE_USER", "trader_test"),
  password: System.get_env("DATABASE_PASSWORD", "caputo"),
  database: System.get_env("DATABASE_NAME", "trade_machine"),
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  port: String.to_integer(System.get_env("STAGING_DATABASE_PORT", "5435")),
  show_sensitive_data_on_connection_error: true,
  pool: Ecto.Adapters.SQL.Sandbox,
  after_connect: {Postgrex, :query!, ["SET search_path TO test", []]},
  priv: "priv/repo/staging"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :trade_machine, TradeMachineWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure Oban for testing - dual instances
config :trade_machine, Oban.Production,
  name: Oban.Production,
  repo: TradeMachine.Repo.Production,
  prefix: "test",
  testing: :manual,
  plugins: false,
  queues: false

config :trade_machine, Oban.Staging,
  name: Oban.Staging,
  repo: TradeMachine.Repo.Staging,
  prefix: "test",
  testing: :manual,
  plugins: false,
  queues: false

# Emailing
config :trade_machine, TradeMachine.Mailer, adapter: Swoosh.Adapters.Test

# HTTP test stubs via Req.Test (retry disabled to keep tests fast)
config :trade_machine, :espn_req_options,
  plug: {Req.Test, TradeMachine.ESPN.Client},
  retry: false

config :trade_machine, :espn_search_req_options,
  plug: {Req.Test, TradeMachine.ESPN.Search},
  retry: false

config :trade_machine, :sheet_fetcher_req_options,
  plug: {Req.Test, TradeMachine.MinorLeagues.SheetFetcher},
  retry: false

# ESPN season year for tests
config :trade_machine, :espn_season_year, 2025
