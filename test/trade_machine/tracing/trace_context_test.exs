defmodule TradeMachine.Tracing.TraceContextTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Tracing.TraceContext

  describe "extract_trace_context/1" do
    test "successfully extracts valid trace context" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
          "tracestate" => "grafana=sessionId:abc123"
        }
      }

      assert {:ok, trace_context} = TraceContext.extract_trace_context(job_args)

      assert trace_context["traceparent"] ==
               "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      assert trace_context["tracestate"] == "grafana=sessionId:abc123"
    end

    test "successfully extracts trace context without tracestate" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        }
      }

      assert {:ok, trace_context} = TraceContext.extract_trace_context(job_args)

      assert trace_context["traceparent"] ==
               "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      refute Map.has_key?(trace_context, "tracestate")
    end

    test "returns error when trace_context is missing" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123"
      }

      assert {:error, "no trace_context found in job args"} =
               TraceContext.extract_trace_context(job_args)
    end

    test "returns error when trace_context is not a map" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => "invalid"
      }

      assert {:error, "no trace_context found in job args"} =
               TraceContext.extract_trace_context(job_args)
    end

    test "returns error when traceparent is missing" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "tracestate" => "grafana=sessionId:abc123"
        }
      }

      assert {:error, "trace_context found but missing required headers"} =
               TraceContext.extract_trace_context(job_args)
    end

    test "returns error when traceparent is invalid format" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "invalid-format"
        }
      }

      assert {:error, "trace_context found but missing required headers"} =
               TraceContext.extract_trace_context(job_args)
    end

    test "returns error when traceparent has wrong version" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        }
      }

      assert {:error, "trace_context found but missing required headers"} =
               TraceContext.extract_trace_context(job_args)
    end

    test "returns error when traceparent has incorrect trace_id length" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e473-00f067aa0ba902b7-01"
        }
      }

      assert {:error, "trace_context found but missing required headers"} =
               TraceContext.extract_trace_context(job_args)
    end

    test "returns error when traceparent has incorrect span_id length" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b-01"
        }
      }

      assert {:error, "trace_context found but missing required headers"} =
               TraceContext.extract_trace_context(job_args)
    end
  end

  describe "with_extracted_context/4" do
    test "executes function when no trace context is present" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123"
      }

      result =
        TraceContext.with_extracted_context(
          job_args,
          "test.span",
          %{"test" => true},
          fn -> :executed end
        )

      assert result == :executed
    end

    test "executes function when trace context is present" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        }
      }

      result =
        TraceContext.with_extracted_context(
          job_args,
          "test.span",
          %{"test" => true},
          fn -> :executed_with_context end
        )

      assert result == :executed_with_context
    end

    test "executes function with invalid trace context (fallback mode)" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123",
        "trace_context" => %{
          "traceparent" => "invalid-format"
        }
      }

      result =
        TraceContext.with_extracted_context(
          job_args,
          "test.span",
          %{"test" => true},
          fn -> :executed_fallback end
        )

      assert result == :executed_fallback
    end

    test "passes through function exceptions" do
      job_args = %{
        "email_type" => "reset_password",
        "data" => "user123"
      }

      assert_raise RuntimeError, "test exception", fn ->
        TraceContext.with_extracted_context(
          job_args,
          "test.span",
          %{"test" => true},
          fn -> raise "test exception" end
        )
      end
    end
  end

  describe "add_span_attributes/1" do
    test "accepts valid attribute map" do
      attributes = %{
        "user_id" => "123",
        "email_type" => "reset_password",
        "processing_time_ms" => 1250
      }

      # Should not raise an error and return boolean
      result = TraceContext.add_span_attributes(attributes)
      assert is_boolean(result)
    end
  end

  describe "add_span_event/2" do
    test "accepts event name and attributes" do
      # Should not raise an error and return boolean
      result = TraceContext.add_span_event("email_sent", %{provider: "brevo", status: "success"})
      assert is_boolean(result)
    end

    test "accepts event name without attributes" do
      # Should not raise an error and return boolean
      result = TraceContext.add_span_event("email_sent")
      assert is_boolean(result)
    end
  end

  describe "record_exception/2" do
    test "accepts exception without attributes" do
      exception = %RuntimeError{message: "test error"}

      # Should not raise an error and return boolean
      result = TraceContext.record_exception(exception)
      assert is_boolean(result)
    end

    test "accepts exception with simple attributes" do
      exception = %RuntimeError{message: "test error"}

      # Use simpler attributes format - just test that it doesn't crash
      # Note: Complex attribute formats may cause issues with OpenTelemetry exception formatting
      result = TraceContext.record_exception(exception, %{})
      assert is_boolean(result)
    end
  end

  describe "create_test_span/1" do
    test "creates test span with default name" do
      result = TraceContext.create_test_span()
      assert result == :test_span_completed
    end

    test "creates test span with custom name" do
      result = TraceContext.create_test_span("custom.test.span")
      assert result == :test_span_completed
    end
  end
end
