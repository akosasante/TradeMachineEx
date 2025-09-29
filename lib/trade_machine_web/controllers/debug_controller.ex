defmodule TradeMachineWeb.DebugController do
  use TradeMachineWeb, :controller

  alias TradeMachine.Tracing.TraceContext

  @moduledoc """
  Debug endpoints for testing and verifying OpenTelemetry tracing setup.

  These endpoints are only available in development and test environments
  to help debug tracing issues without requiring the full application stack.
  """

  def trace(conn, _params) do
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

  def distributed_trace(conn, _params) do
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
        usage: "curl -H \"traceparent: 00-12345678901234567890123456789012-1234567890123456-01\" http://localhost:4000/debug/trace",
        timestamp: DateTime.utc_now()
      })
    end
  end
end