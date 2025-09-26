defmodule TradeMachine.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    # TODO: Replace this with an application var for deployment
    credentials =
      Application.get_env(:trade_machine, :sheets_creds_filepath)
      |> File.read!()
      |> Jason.decode!()

    source =
      {:service_account, credentials, scopes: ["https://www.googleapis.com/auth/spreadsheets"]}

    children = [
      # Google OAuth library. Used to connect to and read from the Minor League and Draft Picks Google Sheet
      {Goth, name: TradeMachine.Goth, source: source},
      # Start the Ecto repository (we connect to the same postgres db as TradeMachineServer)
      TradeMachine.Repo,
      # Start the Telemetry supervisor
      TradeMachineWeb.Telemetry,
      # Start the PubSub system (not currently in use for anything)
      {Phoenix.PubSub, name: TradeMachine.PubSub},
      # Start Oban. This is the queue/job runner that we use to periodically process changes from the Google Sheet
#      {Oban, oban_config()},
      # Start a GenServer whose job is just to keep the spreadsheet id and
      # Google OAuth (Goth) connection in-memory/state
#      {TradeMachine.SheetReader, Application.get_env(:trade_machine, :spreadsheet_id)},
      # Start the Phoenix Endpoint (http/https)
      TradeMachineWeb.Endpoint
    ] ++ dashboard_uploader_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TradeMachine.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TradeMachineWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Returns PromEx dashboard uploader child spec if Grafana is configured
  defp dashboard_uploader_child do
    grafana_host = System.get_env("GRAFANA_HOST")
    grafana_token = System.get_env("GRAFANA_TOKEN")

    if grafana_host && grafana_token do
      [
        {PromEx.DashboardUploader,
         prom_ex_module: TradeMachine.PromEx,
         default_dashboard_opts: []}
      ]
    else
      Logger.info("Skipping PromEx dashboard upload (Grafana not configured)")
      []
    end
  end

#  defp oban_config do
#    Application.fetch_env!(:trade_machine, Oban)
#  end
end
