defmodule TradeMachine.Jobs.DraftPicksSync do
  @moduledoc """
  Oban worker for syncing draft pick data from a public Google Sheet.

  Fetches the sheet as CSV via Req, parses the multi-team layout, then runs the
  sync engine against both Production and Staging databases.

  Schedule: daily at 3:00 AM UTC via cron (configured in config.exs / runtime.exs).
  Queue: `draft_sync`
  """

  use Oban.Worker,
    queue: :draft_sync,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias TradeMachine.DraftPicks.Parser
  alias TradeMachine.DraftPicks.SheetFetcher
  alias TradeMachine.DraftPicks.Sync
  alias TradeMachine.SyncLock
  alias TradeMachine.SyncTracking
  alias TradeMachine.Tracing.TraceContext

  @lock_name :draft_picks_sync

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.info("DraftPicksSync.perform called", job_id: job_id)

    case SyncLock.acquire(@lock_name) do
      :acquired ->
        try do
          result =
            TraceContext.with_extracted_context(
              args,
              "trademachine.elixir.draft_picks_sync.execute",
              %{
                "oban.job_id" => job_id,
                "oban.queue" => "draft_sync",
                "oban.worker" => "TradeMachine.Jobs.DraftPicksSync",
                "service.name" => "trademachine-elixir",
                "component" => "draft_picks_sync"
              },
              fn ->
                execute_sync(job_id)
              end
            )

          Logger.info("DraftPicksSync.perform completed",
            job_id: job_id,
            result: inspect(result)
          )

          result
        after
          SyncLock.release(@lock_name)
        end

      {:already_running, acquired_at} ->
        Logger.warning(
          "DraftPicksSync: another sync is already running (since #{acquired_at}), skipping",
          job_id: job_id
        )

        {:cancel, :already_running}
    end
  end

  defp execute_sync(job_id) do
    trace_id = TraceContext.current_trace_id()
    season = Sync.resolve_season()

    {:ok, execution} =
      SyncTracking.start_sync(:draft_picks_sync, :both,
        oban_job_id: job_id,
        trace_id: trace_id,
        metadata: %{
          "sheet_id" => Application.get_env(:trade_machine, :draft_picks_sheet_id),
          "gid" => Application.get_env(:trade_machine, :draft_picks_sheet_gid, "142978697"),
          "season" => season
        }
      )

    case do_sync() do
      {:ok, stats} ->
        prod_stats = stats.production
        stg_stats = stats.staging

        SyncTracking.complete_sync(execution, %{
          records_processed: prod_stats.upserted + stg_stats.upserted,
          records_updated: prod_stats.upserted + stg_stats.upserted,
          records_skipped: prod_stats.skipped_no_owner + stg_stats.skipped_no_owner,
          metadata: %{
            "season" => season,
            "production" => stringify_stats(prod_stats),
            "staging" => stringify_stats(stg_stats)
          }
        })

        TraceContext.add_span_event("draft_picks_sync.success", %{
          season: season,
          production_upserted: prod_stats.upserted,
          production_skipped: prod_stats.skipped_no_owner,
          staging_upserted: stg_stats.upserted,
          staging_skipped: stg_stats.skipped_no_owner
        })

        Logger.info("Draft picks sync completed successfully",
          season: season,
          production: prod_stats,
          staging: stg_stats
        )

        :ok

      {:error, reason} = error ->
        SyncTracking.fail_sync(execution, inspect(reason))

        TraceContext.add_span_event("draft_picks_sync.error", %{
          error: inspect(reason)
        })

        Logger.error("Draft picks sync failed", error: inspect(reason))
        error
    end
  rescue
    e ->
      Logger.error("Draft picks sync crashed", error: Exception.message(e))
      {:error, Exception.message(e)}
  end

  defp do_sync do
    with {:ok, rows} <- SheetFetcher.fetch_from_config(),
         parsed_picks <- Parser.parse(rows),
         _ <- log_parse_results(parsed_picks),
         {:ok, prod_stats} <-
           Sync.sync_from_sheet(parsed_picks, TradeMachine.Repo.Production),
         {:ok, stg_stats} <-
           Sync.sync_from_sheet(parsed_picks, TradeMachine.Repo.Staging) do
      {:ok, %{production: prod_stats, staging: stg_stats}}
    end
  end

  defp log_parse_results(parsed_picks) do
    owner_counts =
      parsed_picks
      |> Enum.group_by(& &1.type)
      |> Map.new(fn {type, picks} -> {type, length(picks)} end)

    Logger.info("Parsed draft picks sheet",
      pick_count: length(parsed_picks),
      by_type: owner_counts
    )
  end

  defp stringify_stats(stats) do
    Map.new(stats, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
