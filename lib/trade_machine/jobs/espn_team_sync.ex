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
  alias TradeMachine.Teams
  alias TradeMachine.Tracing.TraceContext

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    Logger.info("🏈 EspnTeamSync.perform called", job_id: job_id)

    # Extract trace context and continue distributed trace
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
          Logger.info("📊 Inside TraceContext.with_extracted_context, executing ESPN team sync")
          execute_sync_job()
        end
      )

    Logger.info("✅ EspnTeamSync.perform completed", job_id: job_id, result: inspect(result))
    result
  end

  # Execute the actual sync job logic within the trace context
  defp execute_sync_job do
    # Get season year from application config
    season_year = Application.get_env(:trade_machine, :espn_season_year)

    Logger.info("Starting ESPN team sync", season_year: season_year)

    TraceContext.add_span_attributes(%{
      "espn.season_year" => season_year
    })

    TraceContext.add_span_event("espn.sync.start", %{
      season_year: season_year
    })

    # Create ESPN client for the configured season
    client = Client.new(season_year)

    # Fetch teams from ESPN API
    case Client.get_league_teams(client) do
      {:ok, teams} ->
        handle_teams_fetch_success(teams)

      {:error, reason} = error ->
        handle_teams_fetch_error(reason)
        error
    end
  end

  # Handle successful teams fetch
  defp handle_teams_fetch_success(teams) do
    team_count = length(teams)

    Logger.info("Fetched teams from ESPN", team_count: team_count)

    TraceContext.add_span_attributes(%{
      "espn.teams.count" => team_count
    })

    # Sync teams to database
    case Teams.sync_espn_team_data(teams) do
      {:ok, %{updated: updated, skipped: skipped}} ->
        TraceContext.add_span_event("espn.sync.success", %{
          teams_updated: updated,
          teams_skipped: skipped,
          total_teams: team_count
        })

        TraceContext.add_span_attributes(%{
          "espn.sync.teams_updated" => updated,
          "espn.sync.teams_skipped" => skipped
        })

        Logger.info("ESPN team sync completed successfully",
          updated: updated,
          skipped: skipped,
          total: team_count
        )

        :ok

      {:error, reason} = error ->
        TraceContext.add_span_attributes(%{
          "espn.sync.error.type" => "database_sync_failed"
        })

        TraceContext.record_exception(%RuntimeError{
          message: "Failed to sync teams to database: #{inspect(reason)}"
        })

        TraceContext.add_span_event("espn.sync.error", %{
          error: "database_sync_failed",
          reason: inspect(reason)
        })

        Logger.error("Failed to sync teams to database", error: inspect(reason))
        error
    end
  end

  # Handle ESPN API fetch error
  defp handle_teams_fetch_error(reason) do
    TraceContext.add_span_attributes(%{
      "espn.sync.error.type" => "api_fetch_failed"
    })

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
