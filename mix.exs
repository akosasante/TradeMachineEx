defmodule TradeMachine.MixProject do
  use Mix.Project

  def project do
    [
      app: :trade_machine,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      dialyzer: [ignore_warnings: ".dialyzer.ignore-warnings.exs"],
      deps: deps(),
      releases: [
        trade_machine: [
          cookie: "TEST_COOKIE"
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
      extra_applications: [:logger, :runtime_tools, :logger_file_backend]
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
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 3.2"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_live_dashboard, "~> 0.6.5"},
      {:phoenix_live_reload, "~> 1.3", only: :dev},
      {:phoenix_live_view, "~> 0.17.9"},
      {:ecto_sql, "~> 3.7"},
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},
      {:postgrex, ">= 0.0.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.19.1"},
      {:jason, "~> 1.3"},
      {:plug_cowboy, "~> 2.7"},
      {:oban, "~> 2.11"},
      {:goth, "~> 1.3-rc"},
      {:google_api_sheets, "~> 0.29.3"},
      {:hackney, "~> 1.17"},
      {:logger_file_backend, "~> 0.0.13"},
      {:prom_ex, "~> 1.8"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
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
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": ["esbuild default --minify", "phx.digest"]
    ]
  end
end
