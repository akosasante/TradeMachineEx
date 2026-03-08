defmodule TradeMachine.Jobs.DiscordWorker do
  @moduledoc """
  Oban worker that processes Discord trade announcement jobs.

  Jobs are enqueued by the TypeScript server via direct insertion into the
  `oban_jobs` table. The worker delegates to `TradeMachine.Discord.Announcer`
  for the actual announcement logic.

  ## Job Args

      %{
        "job_type" => "trade_announcement",
        "data" => "trade-uuid",
        "env" => "production" | "staging"
      }
  """

  use Oban.Worker, queue: :discord, max_attempts: 3

  alias TradeMachine.Discord.Announcer

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"job_type" => "trade_announcement", "data" => trade_id, "env" => env}
      }) do
    environment = select_environment(env)

    Logger.info("Processing Discord trade announcement",
      job_id: job_id,
      trade_id: trade_id,
      environment: environment
    )

    case Announcer.announce_trade(trade_id, environment) do
      {:ok, _message} ->
        Logger.info("Discord trade announcement sent successfully",
          job_id: job_id,
          trade_id: trade_id
        )

        :ok

      {:error, reason} = error ->
        Logger.error("Discord trade announcement failed",
          job_id: job_id,
          trade_id: trade_id,
          error: inspect(reason)
        )

        error
    end
  end

  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.error("Invalid Discord job args", job_id: job_id, args: inspect(args))
    {:error, :invalid_args}
  end

  defp select_environment("production"), do: :production
  defp select_environment(_), do: :staging
end
