defmodule TradeMachine.Jobs.EmailWorker do
  use Oban.Worker, queue: :emails, max_attempts: 3
  require Logger

  alias TradeMachine.Mailer
  alias TradeMachine.Tracing.TraceContext

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.info("🚀 EmailWorker.perform called", job_id: job_id, args: args)

    # Build base span attributes, adding user.id (OTel semantic convention) when present
    # so this span can be found via Tempo TraceQL: { .user.id = "X" }
    base_attributes = %{
      "oban.job_id" => job_id,
      "oban.queue" => "emails",
      "oban.worker" => "TradeMachine.Jobs.EmailWorker",
      "email.type" => Map.get(args, "email_type"),
      "service.name" => "trademachine-elixir",
      "component" => "email_worker"
    }

    span_attributes =
      case Map.get(args, "user_id") do
        nil -> base_attributes
        user_id -> Map.put(base_attributes, "user.id", user_id)
      end

    # Extract trace context and continue distributed trace
    result =
      TraceContext.with_extracted_context(
        args,
        "trademachine.elixir.email_worker.execute",
        span_attributes,
        fn ->
          Logger.info("📧 Inside TraceContext.with_extracted_context, executing email job")
          execute_email_job(args)
        end
      )

    Logger.info("✅ EmailWorker.perform completed", job_id: job_id, result: inspect(result))
    result
  end

  # Execute the actual email job logic within the trace context

  # trade_request has a different args shape — no "data" field
  defp execute_email_job(%{
         "email_type" => "trade_request",
         "trade_id" => trade_id,
         "recipient_user_id" => recipient_user_id,
         "accept_url" => accept_url,
         "decline_url" => decline_url,
         "env" => frontend_environment
       }) do
    repo = select_repo(frontend_environment)

    Logger.info("Processing trade_request email job",
      trade_id: trade_id,
      recipient_user_id: recipient_user_id,
      frontend_env: frontend_environment,
      repo: inspect(repo)
    )

    TraceContext.add_span_attributes(%{
      "email.type" => "trade_request",
      "email.trade_id" => trade_id,
      "email.recipient_id" => recipient_user_id,
      "email.frontend_environment" => frontend_environment,
      "email.repo" => inspect(repo)
    })

    handle_email_send(
      "trade_request",
      fn ->
        Mailer.send_trade_request_email(
          trade_id,
          recipient_user_id,
          accept_url,
          decline_url,
          frontend_environment,
          repo
        )
      end,
      trade_id
    )
  end

  # trade_declined — sent to all non-declining participants after a trade is rejected
  defp execute_email_job(
         args = %{
           "email_type" => "trade_declined",
           "trade_id" => trade_id,
           "recipient_user_id" => recipient_user_id,
           "is_creator" => is_creator,
           "env" => frontend_environment
         }
       ) do
    repo = select_repo(frontend_environment)
    decline_url = Map.get(args, "decline_url")

    Logger.info("Processing trade_declined email job",
      trade_id: trade_id,
      recipient_user_id: recipient_user_id,
      is_creator: is_creator,
      frontend_env: frontend_environment,
      repo: inspect(repo)
    )

    TraceContext.add_span_attributes(%{
      "email.type" => "trade_declined",
      "email.trade_id" => trade_id,
      "email.recipient_id" => recipient_user_id,
      "email.is_creator" => is_creator,
      "email.frontend_environment" => frontend_environment,
      "email.repo" => inspect(repo)
    })

    handle_email_send(
      "trade_declined",
      fn ->
        Mailer.send_trade_declined_email(
          trade_id,
          recipient_user_id,
          is_creator,
          decline_url,
          frontend_environment,
          repo
        )
      end,
      trade_id
    )
  end

  # trade_submit — sent to the trade creator once all recipients have accepted, prompting them to finalize
  defp execute_email_job(%{
         "email_type" => "trade_submit",
         "trade_id" => trade_id,
         "recipient_user_id" => recipient_user_id,
         "submit_url" => submit_url,
         "env" => frontend_environment
       }) do
    repo = select_repo(frontend_environment)

    Logger.info("Processing trade_submit email job",
      trade_id: trade_id,
      recipient_user_id: recipient_user_id,
      frontend_env: frontend_environment,
      repo: inspect(repo)
    )

    TraceContext.add_span_attributes(%{
      "email.type" => "trade_submit",
      "email.trade_id" => trade_id,
      "email.recipient_id" => recipient_user_id,
      "email.frontend_environment" => frontend_environment,
      "email.repo" => inspect(repo)
    })

    handle_email_send(
      "trade_submit",
      fn ->
        Mailer.send_trade_submission_email(
          trade_id,
          recipient_user_id,
          submit_url,
          frontend_environment,
          repo
        )
      end,
      trade_id
    )
  end

  defp execute_email_job(%{
         "email_type" => email_type,
         "data" => data,
         "env" => frontend_environment
       }) do
    # Select repo based on environment
    repo = select_repo(frontend_environment)

    Logger.info("Processing email job",
      email_type: email_type,
      data: data,
      frontend_env: frontend_environment,
      repo: inspect(repo)
    )

    TraceContext.add_span_attributes(%{
      "email.type" => email_type,
      "email.recipient_id" => data,
      "email.frontend_environment" => frontend_environment,
      "email.repo" => inspect(repo)
    })

    case email_type do
      "reset_password" ->
        handle_email_send(
          "reset_password",
          fn -> Mailer.send_password_reset_email(data, frontend_environment, repo) end,
          data
        )

      type when type in ["registration", "registration_email"] ->
        handle_email_send(
          "registration",
          fn -> Mailer.send_registration_email(data, frontend_environment, repo) end,
          data
        )

      "test" ->
        handle_email_send(
          "test",
          fn -> Mailer.send_test_email(data, frontend_environment, repo) end,
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

  # Select the appropriate repo based on frontend environment
  defp select_repo("production"), do: TradeMachine.Repo.Production
  defp select_repo(_), do: TradeMachine.Repo.Staging

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
