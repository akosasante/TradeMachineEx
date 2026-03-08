defmodule TradeMachine.Jobs.EmailWebhookWorker do
  use Oban.Worker, queue: :emails, max_attempts: 3

  require Logger

  alias TradeMachine.Data.Email

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

    case repo.insert(
           %Email{message_id: message_id, status: event},
           on_conflict: {:replace, [:status, :updated_at]},
           conflict_target: [:message_id]
         ) do
      {:ok, _} ->
        Logger.info("Email status updated", message_id: message_id, event: event)
        :ok

      {:error, reason} ->
        Logger.error("Failed to update email status",
          message_id: message_id,
          event: event,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Elixir-sent emails include "env" derived from Brevo tags set at send time.
  # TypeScript-sent emails have no tags and default to "production".
  defp select_repo("staging"), do: TradeMachine.Repo.Staging
  defp select_repo(_), do: TradeMachine.Repo.Production
end
