defmodule TradeMachine.PromEx do
  @moduledoc """
  PromEx module for collecting and exposing Prometheus metrics.

  This module configures metrics collection for:
  - Phoenix application metrics (requests, response times, errors)
  - Database/Ecto metrics (query times, connection pool)
  - Oban job processing metrics
  - BEAM VM metrics (memory, processes, garbage collection)
  - Custom business metrics for Google Sheets integration
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

      # Database metrics
      {Plugins.Ecto, repos: [TradeMachine.Repo]},

      # Oban job queue metrics (commented out since Oban is not running)
      # Plugins.Oban,

      # Custom business metrics (temporarily disabled to avoid buckets issue)
      # {TradeMachine.PromEx.CustomMetrics, []}
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
      # Google Sheets health metrics
      sheets_health_polling_metrics(poll_rate),

      # Application-specific metrics
      application_health_polling_metrics(poll_rate)
    ]
  end

  @impl true
  def event_metrics(_opts) do
    [
      # Google Sheets API call metrics
      google_sheets_event_metrics(),

      # Custom telemetry event metrics
      custom_telemetry_event_metrics()
    ]
  end

  defp sheets_health_polling_metrics(poll_rate) do
    Polling.build(
      :trade_machine_sheets_health_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_sheets_health_metrics, []},
      [
        # Google Sheets connection status
        last_value(
          [:trade_machine, :sheets, :connection_status],
          event_name: [:prom_ex, :plugin, :trade_machine, :sheets_health],
          description: "Google Sheets API connection status (1=connected, 0=disconnected)",
          measurement: :connected
        ),

        # Sheet reader process status
        last_value(
          [:trade_machine, :sheets, :reader_status],
          event_name: [:prom_ex, :plugin, :trade_machine, :sheets_health],
          description: "Sheet reader process status (1=alive, 0=dead)",
          measurement: :reader_alive
        )
      ]
    )
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
          measurement: :pool_size
        ),

        # Active database connections
        last_value(
          [:trade_machine, :database, :active_connections],
          event_name: [:prom_ex, :plugin, :trade_machine, :application_health],
          description: "Active database connections",
          measurement: :active_connections
        )
      ]
    )
  end

  defp google_sheets_event_metrics do
    Event.build(
      :trade_machine_google_sheets_event_metrics,
      [
        # API request counter
        counter(
          [:trade_machine, :sheets, :api_requests_total],
          event_name: [:trade_machine, :sheets, :api_request],
          description: "Total number of Google Sheets API requests",
          tags: [:operation, :status]
        ),

        # API request duration
        distribution(
          [:trade_machine, :sheets, :api_request_duration_milliseconds],
          event_name: [:trade_machine, :sheets, :api_request],
          description: "Duration of Google Sheets API requests in milliseconds",
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:operation, :status],
          buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
        )
      ]
    )
  end

  defp custom_telemetry_event_metrics do
    Event.build(
      :trade_machine_custom_telemetry_event_metrics,
      [
        # Oban job queue depth
        last_value(
          [:trade_machine, :oban, :queue_depth],
          event_name: [:oban, :queue, :stats],
          description: "Current depth of Oban job queues",
          measurement: :available,
          tags: [:queue]
        ),

        # Custom health check metrics
        last_value(
          [:trade_machine, :health_check, :status],
          event_name: [:sheets, :health],
          description: "Health check status (1=healthy, 0=unhealthy)",
          measurement: :status,
          tags: [:component]
        )
      ]
    )
  end

  # Callback functions for polling metrics
  def execute_sheets_health_metrics do
    # Check Google Sheets connection
    sheets_connected =
      case Process.whereis(TradeMachine.Goth) do
        pid when is_pid(pid) -> 1
        nil -> 0
      end

    # Check sheet reader process
    reader_alive =
      case Process.whereis(TradeMachine.SheetReader) do
        pid when is_pid(pid) -> 1
        nil -> 0
      end

    :telemetry.execute(
      [:prom_ex, :plugin, :trade_machine, :sheets_health],
      %{
        connected: sheets_connected,
        reader_alive: reader_alive
      },
      %{}
    )
  end

  def execute_application_health_metrics do
    # Get database connection pool information
    try do
      _pool_info = Ecto.Adapters.SQL.query!(TradeMachine.Repo, "SELECT 1", [])

      :telemetry.execute(
        [:prom_ex, :plugin, :trade_machine, :application_health],
        %{
          pool_size: Application.get_env(:trade_machine, TradeMachine.Repo)[:pool_size] || 10,
          active_connections: 1  # This is a simplified metric
        },
        %{}
      )
    rescue
      _ ->
        :telemetry.execute(
          [:prom_ex, :plugin, :trade_machine, :application_health],
          %{
            pool_size: 0,
            active_connections: 0
          },
          %{}
        )
    end
  end
end