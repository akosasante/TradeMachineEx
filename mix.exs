defmodule TradeMachine.MixProject do
  use Mix.Project

  def project do
    [
      app: :trade_machine,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:gettext] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      dialyzer: [ignore_warnings: ".dialyzer.ignore-warnings.exs"],
      deps: deps(),
      releases: [
        trade_machine: [
          cookie: System.get_env("RELEASE_COOKIE", "dev_cookie_please_change_in_production")
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {TradeMachine.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ecto_sql, "~> 3.7"},
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},
      {:gettext, "~> 0.19.1"},
      {:goth, "~> 1.3-rc"},
      {:google_api_sheets, "~> 0.29.3"},
      {:jason, "~> 1.3"},
      {:oban, "~> 2.19"},
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_swoosh, "~> 1.2"},
      {:phoenix_view, "~> 2.0"},
      {:postgrex, ">= 0.0.0"},
      {:premailex, "~> 0.3.0"},
      {:prom_ex, "~> 1.8"},
      {:req, "~> 0.5"},
      {:swoosh, "~> 1.19"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:typed_ecto_schema, "~> 0.4.0", runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      # Database migration strategy: Prisma (TypeScript) handles all schema changes
      # Commented out migration aliases to prevent accidental schema changes from Elixir
      # setup: ["deps.get", "ecto.setup"],
      # "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      # "ecto.reset": ["ecto.drop", "ecto.setup"],
      # test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],

      # Safe aliases that don't modify database schema
      # Only install dependencies
      setup: ["deps.get"],
      # Run tests without migrations
      "test.local": ["cmd ./test.sh"],
      "assets.deploy": ["esbuild default --minify", "phx.digest"]
    ]
  end
end
