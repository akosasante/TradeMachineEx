defmodule TradeMachine.Jobs.EspnMlbPlayersSync do
  @moduledoc """
  Oban worker for syncing ESPN major league player data to the database.

  This job runs daily at 2:32 AM Eastern (7:32 AM UTC) via cron schedule,
  10 minutes after the ESPN team sync to ensure team data is fresh.

  It fetches the full player pool from the ESPN Fantasy API (paginated),
  then runs a multi-phase matching engine to update existing players,
  claim unclaimed ones, and insert new players. Both Production and
  Staging databases are synced.

  ## Observability

  - Uses OpenTelemetry distributed tracing via `TraceContext`
  - Logs structured metadata for debugging
  - Records span events for key milestones
  - Tracks execution via `SyncTracking` with `:mlb_players_sync` job type
  """

  use Oban.Worker,
    queue: :espn_sync,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias TradeMachine.ESPN.Client
  alias TradeMachine.Players
  alias TradeMachine.SyncLock
  alias TradeMachine.SyncTracking
  alias TradeMachine.Tracing.TraceContext

  @lock_name :mlb_players_sync

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.info("EspnMlbPlayersSync.perform called", job_id: job_id)

    case SyncLock.acquire(@lock_name) do
      :acquired ->
        try do
          result =
            TraceContext.with_extracted_context(
              args,
              "trademachine.elixir.espn_mlb_players_sync.execute",
              %{
                "oban.job_id" => job_id,
                "oban.queue" => "espn_sync",
                "oban.worker" => "TradeMachine.Jobs.EspnMlbPlayersSync",
                "service.name" => "trademachine-elixir",
                "component" => "espn_mlb_players_sync"
              },
              fn ->
                execute_sync_job(job_id)
              end
            )

          Logger.info("EspnMlbPlayersSync.perform completed",
            job_id: job_id,
            result: inspect(result)
          )

          result
        after
          SyncLock.release(@lock_name)
        end

      {:already_running, acquired_at} ->
        Logger.warning(
          "EspnMlbPlayersSync: another sync is already running (since #{acquired_at}), skipping",
          job_id: job_id
        )

        {:cancel, :already_running}
    end
  end

  defp execute_sync_job(job_id) do
    season_year = Application.get_env(:trade_machine, :espn_season_year)
    trace_id = TraceContext.current_trace_id()

    {:ok, execution} =
      SyncTracking.start_sync(:mlb_players_sync, :both,
        oban_job_id: job_id,
        trace_id: trace_id,
        metadata: %{"season_year" => season_year}
      )

    Logger.info("Starting ESPN MLB players sync", season_year: season_year)

    TraceContext.add_span_attributes(%{"espn.season_year" => season_year})
    TraceContext.add_span_event("espn.players_sync.start", %{season_year: season_year})

    client = Client.new(season_year)

    case Client.get_all_players(client, raw: true) do
      {:ok, espn_players} ->
        handle_players_fetch_success(espn_players, execution)

      {:error, reason} = error ->
        handle_players_fetch_error(reason, execution)
        error
    end
  end

  defp handle_players_fetch_success(espn_players, execution) do
    player_count = length(espn_players)
    mem_mb = Float.round(:erlang.memory(:total) / 1_048_576, 1)

    Logger.info("Fetched players from ESPN",
      player_count: player_count,
      memory_mb: mem_mb
    )

    TraceContext.add_span_attributes(%{"espn.players.count" => player_count})

    {prod_result, staging_result} = sync_both_repos(espn_players)
    :erlang.garbage_collect()

    case {prod_result, staging_result} do
      {{:ok, prod_stats}, {:ok, staging_stats}} ->
        total_updated = prod_stats.updated + staging_stats.updated
        total_inserted = prod_stats.inserted + staging_stats.inserted
        total_skipped = prod_stats.skipped + staging_stats.skipped

        SyncTracking.complete_sync(execution, %{
          records_processed: player_count * 2,
          records_updated: total_updated + total_inserted,
          records_skipped: total_skipped,
          metadata: %{
            "production" => stringify_stats(prod_stats),
            "staging" => stringify_stats(staging_stats)
          }
        })

        TraceContext.add_span_event("espn.players_sync.success", %{
          production_updated: prod_stats.updated,
          production_inserted: prod_stats.inserted,
          production_skipped: prod_stats.skipped,
          staging_updated: staging_stats.updated,
          staging_inserted: staging_stats.inserted,
          staging_skipped: staging_stats.skipped,
          total_espn_players: player_count
        })

        TraceContext.add_span_attributes(%{
          "espn.sync.production.players_updated" => prod_stats.updated,
          "espn.sync.production.players_inserted" => prod_stats.inserted,
          "espn.sync.production.players_skipped" => prod_stats.skipped,
          "espn.sync.staging.players_updated" => staging_stats.updated,
          "espn.sync.staging.players_inserted" => staging_stats.inserted,
          "espn.sync.staging.players_skipped" => staging_stats.skipped
        })

        Logger.info("ESPN MLB players sync completed successfully",
          production: prod_stats,
          staging: staging_stats,
          total_espn: player_count
        )

        :ok

      {prod_result, staging_result} ->
        errors = collect_errors(prod_result, staging_result)

        SyncTracking.fail_sync(execution, Enum.join(errors, "; "))

        {:error, :sync_failed}
    end
  end

  defp handle_players_fetch_error(reason, execution) do
    SyncTracking.fail_sync(execution, "API fetch failed: #{inspect(reason)}")

    TraceContext.add_span_attributes(%{"espn.sync.error.type" => "api_fetch_failed"})

    TraceContext.record_exception(%RuntimeError{
      message: "Failed to fetch players from ESPN API: #{inspect(reason)}"
    })

    TraceContext.add_span_event("espn.players_sync.error", %{
      error: "api_fetch_failed",
      reason: inspect(reason)
    })

    Logger.error("Failed to fetch players from ESPN API", error: inspect(reason))
  end

  defp sync_both_repos(espn_players) do
    prod_result = Players.sync_espn_player_data(espn_players, TradeMachine.Repo.Production)
    staging_result = Players.sync_espn_player_data(espn_players, TradeMachine.Repo.Staging)
    {prod_result, staging_result}
  end

  defp collect_errors(prod_result, staging_result) do
    errors = []

    errors =
      if match?({:error, _}, prod_result) do
        {:error, reason} = prod_result

        TraceContext.add_span_attributes(%{
          "espn.sync.production.error" => inspect(reason)
        })

        Logger.error("Failed to sync players to production database",
          error: inspect(reason)
        )

        ["production: #{inspect(reason)}" | errors]
      else
        errors
      end

    if match?({:error, _}, staging_result) do
      {:error, reason} = staging_result

      TraceContext.add_span_attributes(%{
        "espn.sync.staging.error" => inspect(reason)
      })

      Logger.error("Failed to sync players to staging database",
        error: inspect(reason)
      )

      ["staging: #{inspect(reason)}" | errors]
    else
      errors
    end
  end

  defp stringify_stats(stats) do
    Map.new(stats, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
