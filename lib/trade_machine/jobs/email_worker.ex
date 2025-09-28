defmodule TradeMachine.Jobs.EmailWorker do
  use Oban.Worker, queue: :emails, max_attempts: 3
  require Logger

  alias TradeMachine.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_type" => email_type, "data" => data}}) do
    case email_type do
      "reset_password" ->
        case Mailer.send_password_reset_email(data) do
          {:ok, _email} -> :ok
          {:error, _reason} = error -> error
        end
      _ ->
        Logger.error("Unknown email type: #{email_type}")
        {:error, :unknown_email_type}
    end
  end
end