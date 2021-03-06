# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :trade_machine,
       ecto_repos: [TradeMachine.Repo],
       sheets_creds_filepath: "/Users/aasante/dev/TradeMachine/TradeMachineServer/sheet_creds.json"

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
       metadata: [:request_id]

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
config :trade_machine, Oban,
  repo: TradeMachine.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: div(:timer.hours(48), 1_000)},
    {Oban.Plugins.Cron, crontab: [{"*/5 * * * *", TradeMachine.Jobs.MinorsSync}]}
  ],
  queues: [minors_sync: 1, draft_sync: 1]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
