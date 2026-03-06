defmodule TradeMachine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    install_signal_handlers()
    initialize_telemetry()

    children =
      [
        # Start both Ecto repositories (Production and Staging)
        TradeMachine.Repo.Production,
        TradeMachine.Repo.Staging,
        # Start the Telemetry supervisor
        TradeMachineWeb.Telemetry,
        # Start the PubSub system (not currently in use for anything)
        {Phoenix.PubSub, name: TradeMachine.PubSub},
        # Start Finch HTTP client (required for Swoosh email adapter)
        {Finch, name: Swoosh.Finch},
        TradeMachine.SyncLock,
        # Start Oban instances - Production handles all jobs including cron, Staging only handles emails
        {Oban,
         Application.fetch_env!(:trade_machine, Oban.Production)
         |> Keyword.put(:name, Oban.Production)},
        {Oban,
         Application.fetch_env!(:trade_machine, Oban.Staging)
         |> Keyword.put(:name, Oban.Staging)},
        # Start the Phoenix Endpoint (http/https)
        TradeMachineWeb.Endpoint
      ] ++ dashboard_uploader_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TradeMachine.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def prep_stop(state) do
    Logger.warning(
      "Application prep_stop called — supervision tree is shutting down. " <>
        "Oban will attempt to finish in-flight jobs within the shutdown grace period."
    )

    state
  end

  @impl true
  def config_change(changed, _new, removed) do
    TradeMachineWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp install_signal_handlers do
    :os.set_signal(:sigterm, :handle)

    spawn(fn -> signal_listener() end)
  end

  defp signal_listener do
    receive do
      {:signal, :sigterm} ->
        Logger.warning(
          "Received SIGTERM — container is being stopped. " <>
            "Initiating graceful shutdown (Oban will attempt to finish in-flight jobs)."
        )

        System.stop(0)
    end
  end

  defp dashboard_uploader_child do
    promex_config = Application.get_env(:trade_machine, TradeMachine.PromEx)
    grafana_host = promex_config[:grafana][:host]
    grafana_token = promex_config[:grafana][:auth_token]
    upload_grafana = Application.get_env(:trade_machine, :upload_grafana_dashboards_on_start)

    if upload_grafana && grafana_host && grafana_token do
      [
        {PromEx.DashboardUploader,
         prom_ex_module: TradeMachine.PromEx, default_dashboard_opts: []}
      ]
    else
      Logger.info("Skipping PromEx dashboard upload (Grafana not configured)")
      []
    end
  end

  # Initialize OpenTelemetry with instrumentation libraries
  defp initialize_telemetry do
    Logger.info("Initializing OpenTelemetry tracing")

    # Configure OpenTelemetry instrumentations
    OpentelemetryOban.setup()
    OpentelemetryEcto.setup([:trade_machine, :repo, :production], time_unit: :millisecond)
    OpentelemetryEcto.setup([:trade_machine, :repo, :staging], time_unit: :millisecond)
    OpentelemetryFinch.setup()

    Logger.info("OpenTelemetry tracing initialized successfully")
  rescue
    error ->
      Logger.error("Failed to initialize OpenTelemetry: #{inspect(error)}")
  end
end
