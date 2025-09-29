defmodule TradeMachineWeb.HealthController do
  use TradeMachineWeb, :controller

  alias TradeMachine.Tracing.TraceContext

  @moduledoc """
  Health check controller for container orchestration and monitoring.

  Provides endpoints for:
  - Basic health check (/health)
  - Readiness check (/ready)
  - Liveness check (/live)
  - Debug trace test (/debug/trace)
  """

  def health(conn, _params) do
    status = perform_health_checks()

    case status.healthy do
      true ->
        conn
        |> put_status(200)
        |> json(status)

      false ->
        conn
        |> put_status(503)
        |> json(status)
    end
  end

  def ready(conn, _params) do
    # Readiness check - can the application serve requests?
    #    ready = database_ready?() && dependencies_ready?()
    ready = database_ready?()

    case ready do
      true ->
        conn
        |> put_status(200)
        |> json(%{status: "ready", timestamp: DateTime.utc_now()})

      false ->
        conn
        |> put_status(503)
        |> json(%{status: "not_ready", timestamp: DateTime.utc_now()})
    end
  end

  def live(conn, _params) do
    # Liveness check - is the application running?
    # This should be lightweight and just check if the app is responsive
    conn
    |> put_status(200)
    |> json(%{status: "alive", timestamp: DateTime.utc_now()})
  end

  def debug_trace(conn, _params) do
    # Create a test span for debugging OpenTelemetry export
    result = TraceContext.create_test_span("debug.api.test")

    conn
    |> put_status(200)
    |> json(%{
      status: "test_span_created",
      result: inspect(result),
      timestamp: DateTime.utc_now(),
      message: "Check Grafana for span with name 'debug.api.test'"
    })
  end

  def debug_distributed_trace(conn, _params) do
    # Extract traceparent header if provided
    traceparent = get_req_header(conn, "traceparent") |> List.first()

    if traceparent do
      # Simulate EmailWorker job args with trace context
      fake_job_args = %{
        "email_type" => "reset_password",
        "data" => "debug_user",
        "trace_context" => %{
          "traceparent" => traceparent
        }
      }

      # Test distributed tracing with the provided traceparent
      result = TraceContext.with_extracted_context(
        fake_job_args,
        "debug.distributed.test",
        %{
          "test.type" => "distributed_trace_debug",
          "service.name" => "trademachine-elixir"
        },
        fn ->
          TraceContext.add_span_event("debug.distributed.test.start", %{})
          Process.sleep(50)  # Add some duration
          TraceContext.add_span_event("debug.distributed.test.end", %{result: "success"})
          :distributed_test_completed
        end
      )

      conn
      |> put_status(200)
      |> json(%{
        status: "distributed_test_completed",
        traceparent: traceparent,
        result: inspect(result),
        timestamp: DateTime.utc_now(),
        message: "Check Grafana for distributed trace with provided traceparent"
      })
    else
      conn
      |> put_status(400)
      |> json(%{
        error: "traceparent header required",
        usage: "curl -H \"traceparent: 00-12345678901234567890123456789012-1234567890123456-01\" http://localhost:4000/debug/distributed-trace",
        timestamp: DateTime.utc_now()
      })
    end
  end

  defp perform_health_checks do
    checks = %{
      database: database_check()
      #      google_sheets: sheets_check(),
      #      oban: oban_check()
    }

    healthy = Enum.all?(checks, fn {_service, status} -> status.healthy end)

    %{
      healthy: healthy,
      timestamp: DateTime.utc_now(),
      service: "trade_machine_ex",
      version: Application.spec(:trade_machine, :vsn) |> to_string(),
      checks: checks
    }
  end

  defp database_check do
    try do
      # Simple database connectivity test
      case Ecto.Adapters.SQL.query(TradeMachine.Repo, "SELECT 1", [], timeout: 5000) do
        {:ok, _} ->
          %{healthy: true, message: "Database connection successful"}

        {:error, error} ->
          %{healthy: false, message: "Database error: #{inspect(error)}"}
      end
    rescue
      error ->
        %{healthy: false, message: "Database exception: #{inspect(error)}"}
    end
  end

  #  defp sheets_check do
  #    try do
  #      # Check if Google Sheets processes are running
  #      goth_alive = Process.whereis(TradeMachine.Goth) != nil
  #      reader_alive = Process.whereis(TradeMachine.SheetReader) != nil
  #
  #      case {goth_alive, reader_alive} do
  #        {true, true} ->
  #          %{healthy: true, message: "Google Sheets integration healthy"}
  #        {false, true} ->
  #          %{healthy: false, message: "Goth (Google Auth) process not running"}
  #        {true, false} ->
  #          %{healthy: false, message: "SheetReader process not running"}
  #        {false, false} ->
  #          %{healthy: false, message: "Both Goth and SheetReader processes not running"}
  #      end
  #    rescue
  #      error ->
  #        %{healthy: false, message: "Sheets check exception: #{inspect(error)}"}
  #    end
  #  end

  #  defp oban_check do
  #    try do
  #      # Check if Oban is running and queues are operational
  #      case Oban.check_queue(TradeMachine.Repo, queue: "minors_sync") do
  #        {:ok, _stats} ->
  #          %{healthy: true, message: "Oban job processing healthy"}
  #        {:error, error} ->
  #          %{healthy: false, message: "Oban error: #{inspect(error)}"}
  #      end
  #    rescue
  #      error ->
  #        %{healthy: false, message: "Oban check exception: #{inspect(error)}"}
  #    end
  #  end

  defp database_ready? do
    try do
      case Ecto.Adapters.SQL.query(TradeMachine.Repo, "SELECT 1", [], timeout: 1000) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    rescue
      _ -> false
    end
  end

  #  defp dependencies_ready? do
  #    # Check critical dependencies are running
  #    Process.whereis(TradeMachine.Goth) != nil &&
  #    Process.whereis(TradeMachine.SheetReader) != nil
  #  end
end
