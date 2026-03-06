defmodule TradeMachine.Jobs.MinorsSync do
  @moduledoc """
  Oban worker for syncing minor league player data from a public Google Sheet.

  Fetches the sheet as CSV via Req, parses the roster layout, then runs the
  matching engine against both Production and Staging databases.

  Schedule: daily at 2:00 AM UTC via cron (configured in runtime.exs).
  """

  use Oban.Worker,
    queue: :minors_sync,
    max_attempts: 5,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  alias TradeMachine.MinorLeagues.Parser
  alias TradeMachine.MinorLeagues.SheetFetcher
  alias TradeMachine.MinorLeagues.Sync
  alias TradeMachine.SyncLock
  alias TradeMachine.SyncTracking
  alias TradeMachine.Tracing.TraceContext

  @lock_name :minors_sync

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.info("MinorsSync.perform called", job_id: job_id)

    case SyncLock.acquire(@lock_name) do
      :acquired ->
        try do
          result =
            TraceContext.with_extracted_context(
              args,
              "trademachine.elixir.minors_sync.execute",
              %{
                "oban.job_id" => job_id,
                "oban.queue" => "minors_sync",
                "oban.worker" => "TradeMachine.Jobs.MinorsSync",
                "service.name" => "trademachine-elixir",
                "component" => "minors_sync"
              },
              fn ->
                execute_sync(job_id)
              end
            )

          Logger.info("MinorsSync.perform completed",
            job_id: job_id,
            result: inspect(result)
          )

          result
        after
          SyncLock.release(@lock_name)
        end

      {:already_running, acquired_at} ->
        Logger.warning(
          "MinorsSync: another sync is already running (since #{acquired_at}), skipping",
          job_id: job_id
        )

        {:cancel, :already_running}
    end
  end

  defp execute_sync(job_id) do
    trace_id = TraceContext.current_trace_id()

    {:ok, execution} =
      SyncTracking.start_sync(:minors_sync, :both,
        oban_job_id: job_id,
        trace_id: trace_id,
        metadata: %{
          "sheet_id" => Application.get_env(:trade_machine, :minor_league_sheet_id),
          "gid" => Application.get_env(:trade_machine, :minor_league_sheet_gid, "806978055")
        }
      )

    case do_sync() do
      {:ok, stats} ->
        prod_stats = stats.production
        stg_stats = stats.staging

        SyncTracking.complete_sync(execution, %{
          records_processed:
            prod_stats.matched + prod_stats.inserted + stg_stats.matched + stg_stats.inserted,
          records_updated: prod_stats.matched + stg_stats.matched,
          records_skipped: prod_stats.skipped_no_owner + stg_stats.skipped_no_owner,
          metadata: %{
            "production" => stringify_stats(prod_stats),
            "staging" => stringify_stats(stg_stats)
          }
        })

        TraceContext.add_span_event("minors_sync.success", %{
          production_matched: prod_stats.matched,
          production_inserted: prod_stats.inserted,
          production_cleared: prod_stats.cleared,
          staging_matched: stg_stats.matched,
          staging_inserted: stg_stats.inserted,
          staging_cleared: stg_stats.cleared
        })

        Logger.info("Minor league sync completed successfully",
          production: prod_stats,
          staging: stg_stats
        )

        :ok

      {:error, reason} = error ->
        SyncTracking.fail_sync(execution, inspect(reason))

        TraceContext.add_span_event("minors_sync.error", %{
          error: inspect(reason)
        })

        Logger.error("Minor league sync failed", error: inspect(reason))
        error
    end
  rescue
    e ->
      Logger.error("Minor league sync crashed", error: Exception.message(e))
      {:error, Exception.message(e)}
  end

  defp do_sync do
    sheet_id = Application.fetch_env!(:trade_machine, :minor_league_sheet_id)
    gid = Application.get_env(:trade_machine, :minor_league_sheet_gid, "806978055")

    with {:ok, rows} <- SheetFetcher.fetch(sheet_id, gid),
         parsed_players <- Parser.parse(rows),
         _ <- log_parse_results(parsed_players),
         {:ok, prod_stats} <- Sync.sync_from_sheet(parsed_players, TradeMachine.Repo.Production),
         {:ok, stg_stats} <- Sync.sync_from_sheet(parsed_players, TradeMachine.Repo.Staging) do
      {:ok, %{production: prod_stats, staging: stg_stats}}
    end
  end

  defp log_parse_results(parsed_players) do
    owners =
      parsed_players
      |> Enum.map(& &1.owner_csv_name)
      |> Enum.uniq()

    Logger.info("Parsed minor league sheet",
      player_count: length(parsed_players),
      owner_count: length(owners),
      owners: owners
    )
  end

  defp stringify_stats(stats) do
    Map.new(stats, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end
