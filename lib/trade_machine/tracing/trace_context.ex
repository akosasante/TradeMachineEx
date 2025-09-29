defmodule TradeMachine.Tracing.TraceContext do
  @moduledoc """
  Utilities for extracting and managing OpenTelemetry trace context
  from Oban job arguments to maintain distributed tracing.

  Uses proper W3C Trace Context propagation via Erlang OpenTelemetry APIs
  to create true parent-child relationships in distributed traces.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

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
    Logger.debug("TraceContext.with_extracted_context called",
      span_name: span_name,
      job_args_keys: Map.keys(job_args)
    )

    case extract_trace_context(job_args) do
      {:ok, trace_context} ->
        traceparent = Map.get(trace_context, "traceparent", "")
        tracestate = Map.get(trace_context, "tracestate", "")
        Logger.info("Extracted trace context, traceparent: #{traceparent}")

        # Use proper OpenTelemetry context propagation
        # Normalize headers for extraction as per documentation
        normalized_headers = [{"traceparent", traceparent}]

        normalized_headers =
          if tracestate != "",
            do: [{"tracestate", tracestate} | normalized_headers],
            else: normalized_headers

        try do
          # Extract context using the official OpenTelemetry propagation API
          :otel_propagator_text_map.extract(normalized_headers)
          Logger.debug("Context extracted using otel_propagator_text_map")

          # Add debugging attributes for trace correlation
          enhanced_attributes =
            Map.merge(span_attributes, %{
              "trace.distributed" => true,
              "trace.parent.traceparent" => traceparent,
              "trace.extracted_with" => "otel_propagator_text_map"
            })

          # Create span within the extracted context
          result =
            Tracer.with_span span_name, enhanced_attributes do
              fun.()
            end

          Logger.debug("Distributed span execution completed with context propagation")
          result
        rescue
          error ->
            Logger.error("Error in context extraction: #{inspect(error)}")

            # Fallback to correlation attributes approach
            parsed_traceparent = parse_traceparent(trace_context)

            correlation_attributes =
              Map.merge(span_attributes, %{
                "trace.distributed" => true,
                "trace.parent.traceparent" => traceparent,
                "trace.parent.trace_id" => parsed_traceparent.trace_id,
                "trace.parent.span_id" => parsed_traceparent.span_id,
                "trace.extraction_error" => inspect(error)
              })

            result =
              Tracer.with_span span_name, correlation_attributes do
                fun.()
              end

            Logger.info("Fallback span execution completed with correlation attributes")
            result
        end

      {:error, reason} ->
        Logger.debug("No trace context found in job args: #{reason}")

        # Create a new root span if no trace context is available
        result =
          Tracer.with_span span_name, span_attributes do
            fun.()
          end

        result
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

  # Check if trace context has the minimum required headers
  defp has_valid_trace_headers?(%{"traceparent" => traceparent}) when is_binary(traceparent) do
    String.match?(traceparent, ~r/^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$/)
  end

  defp has_valid_trace_headers?(_), do: false

  # Parse W3C traceparent header: "00-{trace_id}-{parent_span_id}-{flags}"
  defp parse_traceparent(%{"traceparent" => traceparent}) when is_binary(traceparent) do
    case String.split(traceparent, "-") do
      ["00", trace_id, span_id, flags]
      when byte_size(trace_id) == 32 and byte_size(span_id) == 16 and byte_size(flags) == 2 ->
        %{
          version: "00",
          trace_id: trace_id,
          span_id: span_id,
          flags: flags
        }

      _ ->
        %{
          version: "unknown",
          trace_id: "unknown",
          span_id: "unknown",
          flags: "unknown"
        }
    end
  end

  defp parse_traceparent(_) do
    %{
      version: "missing",
      trace_id: "missing",
      span_id: "missing",
      flags: "missing"
    }
  end

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
    Tracer.set_attributes(attributes)
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
    Tracer.add_event(name, attributes)
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
    Tracer.record_exception(exception, attributes)
  end

  @doc """
  Injects current trace context for outbound calls.

  Returns trace headers that should be included when making HTTP requests
  or creating jobs that need to continue the current trace.

  ## Returns
  A map with trace context headers like `%{"traceparent" => "...", "tracestate" => "..."}`

  ## Example
      trace_headers = TraceContext.inject_trace_context()
      # Include in HTTP request headers or Oban job args
      %{
        "user_id" => user_id,
        "trace_context" => trace_headers
      }
  """
  def inject_trace_context() do
    :otel_propagator_text_map.inject([])
  end

  @doc """
  Creates a simple test span to verify OpenTelemetry export is working.
  This helps debug if the issue is with span creation or distributed tracing.
  """
  def create_test_span(name \\ "test.span") do
    Logger.info("Creating test span: #{name}")

    result =
      Tracer.with_span name, %{
        "test" => true,
        "timestamp" => :os.system_time(:millisecond),
        "service.name" => "trademachine-elixir"
      } do
        # Add some events to make it more visible
        Tracer.add_event("test.start", %{action: "test_span_creation"})
        # Small delay to show duration
        Process.sleep(10)
        Tracer.add_event("test.end", %{result: "success"})

        :test_span_completed
      end

    Logger.debug("Test span completed: #{name}")
    result
  end
end
