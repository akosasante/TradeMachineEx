defmodule TradeMachine.Jobs.EspnTeamSync do
  @moduledoc """
  Oban worker for syncing ESPN team data to the database.

  This job runs daily at 2:22 AM Eastern (7:22 AM UTC) via cron schedule.
  It fetches team data from the ESPN Fantasy API and stores it in the
  `team.espn_team` JSON column for each team, matching by `espn_id`.

  ## Observability

  - Uses OpenTelemetry distributed tracing via `TraceContext`
  - Logs structured metadata for debugging
  - Records span events for key milestones
  - Captures exceptions with full context
  """

  use Oban.Worker, queue: :espn_sync, max_attempts: 3
  require Logger

  alias TradeMachine.ESPN.Client
  alias TradeMachine.SyncTracking
  alias TradeMachine.Teams
  alias TradeMachine.Tracing.TraceContext

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.info("EspnTeamSync.perform called", job_id: job_id)

    result =
      TraceContext.with_extracted_context(
        args,
        "trademachine.elixir.espn_team_sync.execute",
        %{
          "oban.job_id" => job_id,
          "oban.queue" => "espn_sync",
          "oban.worker" => "TradeMachine.Jobs.EspnTeamSync",
          "service.name" => "trademachine-elixir",
          "component" => "espn_team_sync"
        },
        fn ->
          execute_sync_job(job_id)
        end
      )

    Logger.info("EspnTeamSync.perform completed", job_id: job_id, result: inspect(result))
    result
  end

  defp execute_sync_job(job_id) do
    season_year = Application.get_env(:trade_machine, :espn_season_year)
    trace_id = TraceContext.current_trace_id()

    {:ok, execution} =
      SyncTracking.start_sync(:espn_team_sync, :both,
        oban_job_id: job_id,
        trace_id: trace_id,
        metadata: %{"season_year" => season_year}
      )

    Logger.info("Starting ESPN team sync", season_year: season_year)

    TraceContext.add_span_attributes(%{"espn.season_year" => season_year})
    TraceContext.add_span_event("espn.sync.start", %{season_year: season_year})

    client = Client.new(season_year)

    case Client.get_league_teams(client) do
      {:ok, teams} ->
        handle_teams_fetch_success(teams, execution)

      {:error, reason} = error ->
        handle_teams_fetch_error(reason, execution)
        error
    end
  end

  defp handle_teams_fetch_success(teams, execution) do
    team_count = length(teams)

    Logger.info("Fetched teams from ESPN", team_count: team_count)

    TraceContext.add_span_attributes(%{"espn.teams.count" => team_count})

    prod_result = Teams.sync_espn_team_data(teams, TradeMachine.Repo.Production)
    staging_result = Teams.sync_espn_team_data(teams, TradeMachine.Repo.Staging)

    case {prod_result, staging_result} do
      {{:ok, prod_stats}, {:ok, staging_stats}} ->
        total_updated = prod_stats.updated + staging_stats.updated
        total_skipped = prod_stats.skipped + staging_stats.skipped

        SyncTracking.complete_sync(execution, %{
          records_processed: team_count * 2,
          records_updated: total_updated,
          records_skipped: total_skipped,
          metadata: %{
            "production" => prod_stats,
            "staging" => staging_stats
          }
        })

        TraceContext.add_span_event("espn.sync.success", %{
          production_updated: prod_stats.updated,
          production_skipped: prod_stats.skipped,
          staging_updated: staging_stats.updated,
          staging_skipped: staging_stats.skipped,
          total_teams: team_count
        })

        TraceContext.add_span_attributes(%{
          "espn.sync.production.teams_updated" => prod_stats.updated,
          "espn.sync.production.teams_skipped" => prod_stats.skipped,
          "espn.sync.staging.teams_updated" => staging_stats.updated,
          "espn.sync.staging.teams_skipped" => staging_stats.skipped
        })

        Logger.info("ESPN team sync completed successfully",
          production: prod_stats,
          staging: staging_stats,
          total: team_count
        )

        :ok

      {prod_result, staging_result} ->
        errors = []

        errors =
          if match?({:error, _}, prod_result) do
            {:error, prod_reason} = prod_result

            TraceContext.add_span_attributes(%{
              "espn.sync.production.error" => inspect(prod_reason)
            })

            Logger.error("Failed to sync teams to production database",
              error: inspect(prod_reason)
            )

            ["production: #{inspect(prod_reason)}" | errors]
          else
            errors
          end

        errors =
          if match?({:error, _}, staging_result) do
            {:error, staging_reason} = staging_result

            TraceContext.add_span_attributes(%{
              "espn.sync.staging.error" => inspect(staging_reason)
            })

            Logger.error("Failed to sync teams to staging database",
              error: inspect(staging_reason)
            )

            ["staging: #{inspect(staging_reason)}" | errors]
          else
            errors
          end

        SyncTracking.fail_sync(execution, Enum.join(errors, "; "))

        {:error, :sync_failed}
    end
  end

  defp handle_teams_fetch_error(reason, execution) do
    SyncTracking.fail_sync(execution, "API fetch failed: #{inspect(reason)}")

    TraceContext.add_span_attributes(%{"espn.sync.error.type" => "api_fetch_failed"})

    TraceContext.record_exception(%RuntimeError{
      message: "Failed to fetch teams from ESPN API: #{inspect(reason)}"
    })

    TraceContext.add_span_event("espn.sync.error", %{
      error: "api_fetch_failed",
      reason: inspect(reason)
    })

    Logger.error("Failed to fetch teams from ESPN API", error: inspect(reason))
  end
end
