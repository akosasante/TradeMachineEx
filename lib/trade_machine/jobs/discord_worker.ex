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
  alias TradeMachine.Tracing.TraceContext

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"job_type" => "trade_announcement", "data" => trade_id, "env" => env} = args
      }) do
    environment = select_environment(env)

    Logger.info("Processing Discord trade announcement",
      job_id: job_id,
      trade_id: trade_id,
      environment: environment
    )

    TraceContext.with_extracted_context(
      args,
      "trademachine.elixir.discord_worker.execute",
      %{
        "oban.job_id" => job_id,
        "oban.queue" => "discord",
        "oban.worker" => "TradeMachine.Jobs.DiscordWorker",
        "discord.trade_id" => trade_id,
        "discord.environment" => to_string(environment),
        "service.name" => "trademachine-elixir",
        "component" => "discord_worker"
      },
      fn -> announce(job_id, trade_id, environment) end
    )
  end

  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.error("Invalid Discord job args", job_id: job_id, args: inspect(args))
    {:error, :invalid_args}
  end

  defp announce(job_id, trade_id, environment) do
    case Announcer.announce_trade(trade_id, environment) do
      {:ok, _message} ->
        Logger.info("Discord trade announcement sent successfully",
          job_id: job_id,
          trade_id: trade_id
        )

        :ok

      {:error, reason} = error ->
        TraceContext.record_exception(%RuntimeError{
          message: "Discord announcement failed: #{inspect(reason)}"
        })

        TraceContext.add_span_event("discord.announce.error", %{
          trade_id: trade_id,
          error: inspect(reason)
        })

        Logger.error("Discord trade announcement failed",
          job_id: job_id,
          trade_id: trade_id,
          error: inspect(reason)
        )

        error
    end
  end

  defp select_environment("production"), do: :production
  defp select_environment(_), do: :staging
end
