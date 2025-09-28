defmodule TradeMachine.Tracing.TraceContext do
  @moduledoc """
  Utilities for extracting and managing OpenTelemetry trace context
  from Oban job arguments to maintain distributed tracing.
  """

  require Logger
  require OpenTelemetry.Tracer

  @doc """
  Extracts trace context from Oban job args and executes a function within that context.

  This function looks for trace context data in the job args (typically injected by
  the TypeScript server) and sets up the OpenTelemetry context to continue the
  distributed trace.

  ## Parameters
  - `job_args` - The Oban job arguments map that may contain trace_context
  - `span_name` - Name for the span to be created
  - `span_attributes` - Additional attributes to add to the span
  - `fun` - Function to execute within the trace context

  ## Returns
  The result of executing the function within the trace context.

  ## Example
      trace_context = %{
        "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        "tracestate" => "grafana=sessionId:abc123"
      }

      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => trace_context
      }

      TraceContext.with_extracted_context(job_args, "email_job.execute", %{job_id: 123}, fn ->
        # Your job logic here - will be traced as part of the distributed trace
        send_email()
      end)
  """
  def with_extracted_context(job_args, span_name, span_attributes \\ %{}, fun) do
    case extract_trace_context(job_args) do
      {:ok, trace_context} ->
        Logger.debug("Extracted trace context from job args: #{inspect(trace_context)}")

        # Convert trace context to OpenTelemetry span context
        span_context = parse_trace_context(trace_context)

        # Create and execute within a span using the extracted context
        OpenTelemetry.Tracer.with_span(
          span_name,
          %{
            parent: span_context,
            attributes: span_attributes
          },
          fun
        )

      {:error, reason} ->
        Logger.debug("No trace context found in job args, creating new trace: #{reason}")

        # Create a new root span if no trace context is available
        OpenTelemetry.Tracer.with_span(
          span_name,
          %{attributes: span_attributes},
          fun
        )
    end
  end

  @doc """
  Extracts trace context from Oban job arguments.

  Looks for a "trace_context" key in the job args that should contain
  W3C trace context headers.

  ## Parameters
  - `job_args` - The Oban job arguments map

  ## Returns
  - `{:ok, trace_context}` if trace context is found
  - `{:error, reason}` if no trace context is available
  """
  def extract_trace_context(%{"trace_context" => trace_context}) when is_map(trace_context) do
    if has_valid_trace_headers?(trace_context) do
      {:ok, trace_context}
    else
      {:error, "trace_context found but missing required headers"}
    end
  end

  def extract_trace_context(_job_args) do
    {:error, "no trace_context found in job args"}
  end

  # Parse W3C trace context headers into OpenTelemetry span context
  defp parse_trace_context(%{"traceparent" => traceparent} = trace_context) do
    case parse_traceparent(traceparent) do
      {:ok, {trace_id, span_id, trace_flags}} ->
        tracestate = Map.get(trace_context, "tracestate", "")

        OpenTelemetry.trace_context_from_hex(
          trace_id,
          span_id,
          trace_flags,
          tracestate
        )

      {:error, _reason} ->
        nil
    end
  end

  defp parse_trace_context(_) do
    nil
  end

  # Parse W3C traceparent header format:
  # 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
  defp parse_traceparent(traceparent) when is_binary(traceparent) do
    case String.split(traceparent, "-") do
      [version, trace_id, span_id, trace_flags] when version == "00" ->
        try do
          trace_id_int = String.to_integer(trace_id, 16)
          span_id_int = String.to_integer(span_id, 16)
          trace_flags_int = String.to_integer(trace_flags, 16)

          {:ok, {trace_id_int, span_id_int, trace_flags_int}}
        rescue
          ArgumentError ->
            {:error, "invalid hex values in traceparent"}
        end

      _ ->
        {:error, "invalid traceparent format"}
    end
  end

  defp parse_traceparent(_), do: {:error, "traceparent is not a string"}

  # Check if trace context has the minimum required headers
  defp has_valid_trace_headers?(%{"traceparent" => traceparent}) when is_binary(traceparent) do
    String.match?(traceparent, ~r/^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$/)
  end

  defp has_valid_trace_headers?(_), do: false

  @doc """
  Adds custom attributes to the current active span.

  ## Parameters
  - `attributes` - Map of attribute key-value pairs to add

  ## Example
      TraceContext.add_span_attributes(%{
        user_id: "123",
        email_type: "reset_password",
        processing_time_ms: 1250
      })
  """
  def add_span_attributes(attributes) when is_map(attributes) do
    OpenTelemetry.Tracer.set_attributes(attributes)
  end

  @doc """
  Records an event on the current active span.

  ## Parameters
  - `name` - Event name
  - `attributes` - Optional event attributes

  ## Example
      TraceContext.add_span_event("email_sent", %{provider: "brevo", status: "success"})
  """
  def add_span_event(name, attributes \\ %{}) do
    OpenTelemetry.Tracer.add_event(name, attributes)
  end

  @doc """
  Records an exception on the current active span.

  ## Parameters
  - `exception` - The exception to record
  - `attributes` - Optional additional attributes

  ## Example
      TraceContext.record_exception(error, %{retry_attempt: 2})
  """
  def record_exception(exception, attributes \\ %{}) do
    OpenTelemetry.Tracer.record_exception(exception, attributes)
  end
end