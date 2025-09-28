defmodule TradeMachine.Jobs.EmailWorker do
  use Oban.Worker, queue: :emails, max_attempts: 3
  require Logger

  alias TradeMachine.Mailer
  alias TradeMachine.Tracing.TraceContext

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args} = job) do
    # Extract trace context and continue distributed trace
    TraceContext.with_extracted_context(
      args,
      "email_job.process",
      %{
        job_id: job_id,
        queue: "emails",
        worker: "EmailWorker",
        email_type: Map.get(args, "email_type")
      },
      fn ->
        execute_email_job(args)
      end
    )
  end

  # Execute the actual email job logic within the trace context
  defp execute_email_job(%{"email_type" => email_type, "data" => data}) do
    Logger.info("Processing email job", email_type: email_type, data: data)

    TraceContext.add_span_attributes(%{
      "email.type" => email_type,
      "email.recipient_id" => data
    })

    case email_type do
      "reset_password" ->
        TraceContext.add_span_event("email.send.start", %{type: "reset_password"})

        case Mailer.send_password_reset_email(data) do
          {:ok, _email} ->
            TraceContext.add_span_event("email.send.success", %{
              email_type: "reset_password",
              provider: "brevo"
            })

            Logger.info("Password reset email sent successfully", user_id: data)
            :ok

          {:error, reason} = error ->
            TraceContext.record_exception(
              %RuntimeError{message: "Email send failed: #{inspect(reason)}"},
              %{email_type: email_type, user_id: data}
            )

            TraceContext.add_span_event("email.send.error", %{
              email_type: "reset_password",
              error: inspect(reason)
            })

            Logger.error("Failed to send password reset email",
              user_id: data,
              error: inspect(reason)
            )

            error
        end

      _ ->
        error_msg = "Unknown email type: #{email_type}"

        TraceContext.record_exception(
          %RuntimeError{message: error_msg},
          %{email_type: email_type}
        )

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

    TraceContext.record_exception(
      %RuntimeError{message: error_msg},
      %{job_args: inspect(args)}
    )

    Logger.error(error_msg)
    {:error, :invalid_args}
  end
end
