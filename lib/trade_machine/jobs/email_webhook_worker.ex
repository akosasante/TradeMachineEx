defmodule TradeMachine.Jobs.EmailWebhookWorker do
  use Oban.Worker, queue: :emails, max_attempts: 3

  require Logger

  alias TradeMachine.Data.Email
  alias TradeMachine.Tracing.TraceContext

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"message_id" => message_id, "event" => event} = args}) do
    env = Map.get(args, "env", "production")
    repo = select_repo(env)

    Logger.info("Processing email webhook status update",
      job_id: job_id,
      message_id: message_id,
      event: event,
      env: env
    )

    TraceContext.with_extracted_context(
      args,
      "trademachine.elixir.email_webhook_worker.execute",
      %{
        "oban.job_id" => job_id,
        "oban.queue" => "emails",
        "oban.worker" => "TradeMachine.Jobs.EmailWebhookWorker",
        "email.message_id" => message_id,
        "email.event" => event,
        "email.env" => env,
        "service.name" => "trademachine-elixir",
        "component" => "email_webhook_worker"
      },
      fn ->
        TraceContext.add_span_event("email_webhook.upsert.start", %{
          message_id: message_id,
          event: event
        })

        changeset = Email.changeset(%Email{message_id: message_id}, %{"status" => event})

        case repo.insert(
               changeset,
               on_conflict: {:replace, [:status, :updated_at]},
               conflict_target: [:message_id]
             ) do
          {:ok, _} ->
            TraceContext.add_span_event("email_webhook.upsert.success", %{
              message_id: message_id,
              event: event
            })

            Logger.info("Email status updated", message_id: message_id, event: event)
            :ok

          {:error, reason} ->
            TraceContext.record_exception(%RuntimeError{
              message: "Email webhook upsert failed: #{inspect(reason)}"
            })

            TraceContext.add_span_event("email_webhook.upsert.error", %{
              message_id: message_id,
              error: inspect(reason)
            })

            Logger.error("Failed to update email status",
              message_id: message_id,
              event: event,
              error: inspect(reason)
            )

            {:error, reason}
        end
      end
    )
  end

  # Elixir-sent emails include "env" derived from Brevo tags set at send time.
  # TypeScript-sent emails have no tags and default to "production".
  defp select_repo("staging"), do: TradeMachine.Repo.Staging
  defp select_repo(_), do: TradeMachine.Repo.Production
end
