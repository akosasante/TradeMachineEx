defmodule TradeMachine.Jobs.EmailWorker do
  use Oban.Worker, queue: :emails, max_attempts: 3
  require Logger

  alias TradeMachine.Mailer
  alias TradeMachine.Tracing.TraceContext

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.info("🚀 EmailWorker.perform called", job_id: job_id, args: args)

    # Extract trace context and continue distributed trace
    result =
      TraceContext.with_extracted_context(
        args,
        "trademachine.elixir.email_worker.execute",
        %{
          "oban.job_id" => job_id,
          "oban.queue" => "emails",
          "oban.worker" => "TradeMachine.Jobs.EmailWorker",
          "email.type" => Map.get(args, "email_type"),
          "service.name" => "trademachine-elixir",
          "component" => "email_worker"
        },
        fn ->
          Logger.info("📧 Inside TraceContext.with_extracted_context, executing email job")
          execute_email_job(args)
        end
      )

    Logger.info("✅ EmailWorker.perform completed", job_id: job_id, result: inspect(result))
    result
  end

  # Execute the actual email job logic within the trace context
  defp execute_email_job(%{
         "email_type" => email_type,
         "data" => data,
         "env" => frontend_environment
       }) do
    Logger.info("Processing email job",
      email_type: email_type,
      data: data,
      frontend_env: frontend_environment
    )

    TraceContext.add_span_attributes(%{
      "email.type" => email_type,
      "email.recipient_id" => data,
      "email.frontend_environment" => frontend_environment
    })

    case email_type do
      "reset_password" ->
        handle_email_send(
          "reset_password",
          fn -> Mailer.send_password_reset_email(data, frontend_environment) end,
          data
        )

      "registration" ->
        handle_email_send(
          "registration",
          fn -> Mailer.send_registration_email(data, frontend_environment) end,
          data
        )

      "test" ->
        handle_email_send(
          "test",
          fn -> Mailer.send_test_email(data, frontend_environment) end,
          data
        )

      _ ->
        error_msg = "Unknown email type: #{email_type}"

        TraceContext.add_span_attributes(%{
          "email.error.unknown_type" => email_type
        })

        TraceContext.record_exception(%RuntimeError{message: error_msg})

        TraceContext.add_span_event("email.send.error", %{
          error: "unknown_email_type",
          email_type: email_type
        })

        Logger.error(error_msg)
        {:error, :unknown_email_type}
    end
  end

  # Fallback for jobs without required fields
  defp execute_email_job(args) do
    error_msg = "Invalid email job args: #{inspect(args)}"

    TraceContext.add_span_attributes(%{
      "email.error.invalid_args" => inspect(args)
    })

    TraceContext.record_exception(%RuntimeError{message: error_msg})

    Logger.error(error_msg)
    {:error, :invalid_args}
  end

  # Helper function to handle email sending with tracing and error handling
  defp handle_email_send(email_type, send_fn, user_id) do
    TraceContext.add_span_event("email.send.start", %{type: email_type})

    case send_fn.() do
      {:ok, _email} ->
        TraceContext.add_span_event("email.send.success", %{
          email_type: email_type,
          provider: "brevo"
        })

        Logger.info("#{String.capitalize(email_type)} email sent successfully", user_id: user_id)
        :ok

      {:error, reason} = error ->
        TraceContext.add_span_attributes(%{
          "email.error.type" => email_type,
          "email.error.user_id" => user_id
        })

        TraceContext.record_exception(%RuntimeError{
          message: "Email send failed: #{inspect(reason)}"
        })

        TraceContext.add_span_event("email.send.error", %{
          email_type: email_type,
          error: inspect(reason)
        })

        Logger.error("Failed to send #{email_type} email",
          user_id: user_id,
          error: inspect(reason)
        )

        error
    end
  end
end
