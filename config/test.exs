use Mix.Config

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Configuring postgres schema to use for all queries
query_args = ["SET search_path TO dev", []]

# Configure your database
config :trade_machine, TradeMachine.Repo,
  username: "trader_test",
  password: "caputo",
  database: "trade_machine",
  #  database: "trade_machine_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool: Ecto.Adapters.SQL.Sandbox,
  after_connect: {Postgrex, :query!, query_args}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :trade_machine, TradeMachineWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Turn off Oban queues during testing
config :trade_machine, Oban,
  plugins: false,
  queues: false
