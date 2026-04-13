defmodule TradeMachine.Jobs.DiscordWorker do
  @moduledoc """
  Oban worker that processes Discord jobs: channel trade announcements and trade action DMs.

  Jobs are enqueued by the TypeScript server via direct insertion into the
  `oban_jobs` table.

  ## Job Args

  Announcement:

      %{"job_type" => "trade_announcement", "data" => "trade-uuid", "env" => "production" | "staging"}

  Direct messages (URLs mirror email jobs, snake_case keys):

      %{"job_type" => "trade_request_dm", "trade_id" => ..., "recipient_user_id" => ...,
        "accept_url" => ..., "decline_url" => ..., "env" => ...}

      %{"job_type" => "trade_submit_dm", "trade_id" => ..., "recipient_user_id" => ...,
        "submit_url" => ..., "env" => ...}

      %{"job_type" => "trade_declined_dm", "trade_id" => ..., "recipient_user_id" => ...,
        "is_creator" => true | false, "decline_url" => optional, "env" => ...}
  """

  use Oban.Worker, queue: :discord, max_attempts: 3

  alias TradeMachine.Discord.ActionDm
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

  def perform(%Oban.Job{
        id: job_id,
        args:
          %{
            "job_type" => "trade_request_dm",
            "trade_id" => trade_id,
            "recipient_user_id" => recipient_user_id,
            "accept_url" => accept_url,
            "decline_url" => decline_url,
            "env" => env
          } = args
      }) do
    repo = select_repo(env)
    notification_settings_url = Map.get(args, "notification_settings_url")

    TraceContext.with_extracted_context(
      args,
      "trademachine.elixir.discord_worker.execute",
      dm_span_attrs(job_id, "trade_request_dm", trade_id, recipient_user_id),
      fn ->
        Logger.info("Processing Discord trade_request_dm",
          job_id: job_id,
          trade_id: trade_id,
          recipient_user_id: recipient_user_id
        )

        result =
          ActionDm.send_trade_request_dm(
            trade_id,
            recipient_user_id,
            accept_url,
            decline_url,
            repo,
            notification_settings_url
          )

        finalize_dm_job(job_id, trade_id, "trade_request_dm", result)
      end
    )
  end

  def perform(%Oban.Job{
        id: job_id,
        args:
          %{
            "job_type" => "trade_submit_dm",
            "trade_id" => trade_id,
            "recipient_user_id" => recipient_user_id,
            "submit_url" => submit_url,
            "env" => env
          } = args
      }) do
    repo = select_repo(env)
    notification_settings_url = Map.get(args, "notification_settings_url")

    TraceContext.with_extracted_context(
      args,
      "trademachine.elixir.discord_worker.execute",
      dm_span_attrs(job_id, "trade_submit_dm", trade_id, recipient_user_id),
      fn ->
        Logger.info("Processing Discord trade_submit_dm",
          job_id: job_id,
          trade_id: trade_id,
          recipient_user_id: recipient_user_id
        )

        result =
          ActionDm.send_trade_submit_dm(
            trade_id,
            recipient_user_id,
            submit_url,
            repo,
            notification_settings_url
          )

        finalize_dm_job(job_id, trade_id, "trade_submit_dm", result)
      end
    )
  end

  def perform(%Oban.Job{
        id: job_id,
        args:
          %{
            "job_type" => "trade_declined_dm",
            "trade_id" => trade_id,
            "recipient_user_id" => recipient_user_id,
            "env" => env
          } = args
      }) do
    repo = select_repo(env)
    is_creator = Map.get(args, "is_creator", false)
    decline_url = Map.get(args, "decline_url")
    notification_settings_url = Map.get(args, "notification_settings_url")

    TraceContext.with_extracted_context(
      args,
      "trademachine.elixir.discord_worker.execute",
      dm_span_attrs(job_id, "trade_declined_dm", trade_id, recipient_user_id),
      fn ->
        Logger.info("Processing Discord trade_declined_dm",
          job_id: job_id,
          trade_id: trade_id,
          recipient_user_id: recipient_user_id
        )

        result =
          ActionDm.send_trade_declined_dm(
            trade_id,
            recipient_user_id,
            is_creator,
            decline_url,
            repo,
            notification_settings_url
          )

        finalize_dm_job(job_id, trade_id, "trade_declined_dm", result)
      end
    )
  end

  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.error("Invalid Discord job args", job_id: job_id, args: inspect(args))
    {:error, :invalid_args}
  end

  defp dm_span_attrs(job_id, dm_kind, trade_id, recipient_user_id) do
    %{
      "oban.job_id" => job_id,
      "oban.queue" => "discord",
      "oban.worker" => "TradeMachine.Jobs.DiscordWorker",
      "discord.job_type" => dm_kind,
      "discord.trade_id" => trade_id,
      "discord.recipient_user_id" => recipient_user_id,
      "user.id" => recipient_user_id,
      "service.name" => "trademachine-elixir",
      "component" => "discord_worker"
    }
  end

  defp finalize_dm_job(job_id, trade_id, kind, result) do
    case result do
      {:ok, _message} ->
        Logger.info("Discord DM job completed", job_id: job_id, trade_id: trade_id, kind: kind)
        :ok

      {:error, reason}
      when reason in [
             :no_discord_user_id,
             :invalid_discord_user_id,
             :trade_not_found,
             :user_not_found,
             :discord_dm_disabled_by_user
           ] ->
        Logger.info("Discord DM skipped (non-retryable)",
          job_id: job_id,
          trade_id: trade_id,
          kind: kind,
          reason: reason
        )

        :ok

      {:error, reason} = err ->
        Logger.error("Discord DM failed",
          job_id: job_id,
          trade_id: trade_id,
          kind: kind,
          error: inspect(reason)
        )

        err
    end
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

  defp select_repo("production"), do: TradeMachine.Repo.Production
  defp select_repo(_), do: TradeMachine.Repo.Staging
end
