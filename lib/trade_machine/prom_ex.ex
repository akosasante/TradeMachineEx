defmodule TradeMachine.PromEx do
  @moduledoc """
  PromEx module for collecting and exposing Prometheus metrics.

  This module configures metrics collection for:
  - Phoenix application metrics (requests, response times, errors)
  - Database/Ecto metrics (query times, connection pool)
  - Oban job processing metrics
  - BEAM VM metrics (memory, processes, garbage collection)
  - Custom business metrics (application health, Oban queues)
  """

  use PromEx, otp_app: :trade_machine

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # Core BEAM VM metrics
      Plugins.Application,
      Plugins.Beam,

      # Phoenix web metrics
      {Plugins.Phoenix, endpoint: TradeMachineWeb.Endpoint, router: TradeMachineWeb.Router},

      # Database metrics - monitor both Production and Staging repos
      {Plugins.Ecto, repos: [TradeMachine.Repo.Production, TradeMachine.Repo.Staging]},

      # Oban job queue metrics - monitors both Production and Staging instances
      {Plugins.Oban, oban_supervisors: [Oban.Production, Oban.Staging]}
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "Prometheus",
      default_selected_interval: "30s",
      otp_app: :trade_machine
    ]
  end

  @impl true
  def dashboards do
    [
      # Built-in dashboards
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"},

      # Custom dashboard for business metrics
      {:trade_machine, "business_metrics.json"}
    ]
  end
end

defmodule TradeMachine.PromEx.CustomMetrics do
  @moduledoc """
  Custom Prometheus metrics plugin for TradeMachine-specific business metrics.
  """

  use PromEx.Plugin

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      application_health_polling_metrics(poll_rate)
    ]
  end

  @impl true
  def event_metrics(_opts) do
    [
      custom_telemetry_event_metrics()
    ]
  end

  defp application_health_polling_metrics(poll_rate) do
    Polling.build(
      :trade_machine_application_health_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_application_health_metrics, []},
      [
        # Database connection pool usage
        last_value(
          [:trade_machine, :database, :pool_size],
          event_name: [:prom_ex, :plugin, :trade_machine, :application_health],
          description: "Database connection pool size",
          measurement: :pool_size,
          tags: [:repo]
        ),

        # Active database connections
        last_value(
          [:trade_machine, :database, :active_connections],
          event_name: [:prom_ex, :plugin, :trade_machine, :application_health],
          description: "Active database connections",
          measurement: :active_connections,
          tags: [:repo]
        )
      ]
    )
  end

  defp custom_telemetry_event_metrics do
    Event.build(
      :trade_machine_custom_telemetry_event_metrics,
      [
        last_value(
          [:trade_machine, :oban, :queue_depth],
          event_name: [:oban, :queue, :stats],
          description: "Current depth of Oban job queues",
          measurement: :available,
          tags: [:queue]
        )
      ]
    )
  end

  def execute_application_health_metrics do
    # Emit metrics for both Production and Staging repos
    emit_repo_health_metrics(TradeMachine.Repo.Production, "production")
    emit_repo_health_metrics(TradeMachine.Repo.Staging, "staging")
  end

  defp emit_repo_health_metrics(repo, repo_name) do
    try do
      # Test database connectivity
      _pool_info = Ecto.Adapters.SQL.query!(repo, "SELECT 1", [])

      :telemetry.execute(
        [:prom_ex, :plugin, :trade_machine, :application_health],
        %{
          pool_size: Application.get_env(:trade_machine, repo)[:pool_size] || 10,
          # This is a simplified metric - in production you could get actual pool stats
          active_connections: 1
        },
        %{repo: repo_name}
      )
    rescue
      _ ->
        # If query fails, emit zero metrics to indicate unhealthy state
        :telemetry.execute(
          [:prom_ex, :plugin, :trade_machine, :application_health],
          %{
            pool_size: 0,
            active_connections: 0
          },
          %{repo: repo_name}
        )
    end
  end
end
