alias Elixir.TradeMachine.Data.DraftPick
alias Elixir.TradeMachine.Data.Email
alias Elixir.TradeMachine.Data.HydratedMajor
alias Elixir.TradeMachine.Data.HydratedMinor
alias Elixir.TradeMachine.Data.HydratedPick
alias Elixir.TradeMachine.Data.HydratedTrade
alias Elixir.TradeMachine.Data.Player
alias Elixir.TradeMachine.Data.Settings
alias Elixir.TradeMachine.Data.Team
alias Elixir.TradeMachine.Data.Trade
alias Elixir.TradeMachine.Data.TradeItem
alias Elixir.TradeMachine.Data.TradeParticipant
alias Elixir.TradeMachine.Data.User

alias TradeMachine.Repo
alias TradeMachine.ESPN.Client
alias TradeMachine.ESPN.Constants
alias TradeMachine.Players
alias TradeMachine.SyncLock
alias TradeMachine.SyncTracking

require Ecto.Query
import Ecto.Query

defmodule EspnPlayerSync do
  @moduledoc """
  IEx helpers for testing the ESPN MLB player sync locally.

  ## Quick start

      # Fetch all ESPN players (paginated, takes a few minutes)
      espn_players = EspnPlayerSync.fetch_players()

      # Preview what the sync would do (dry-run against prod)
      EspnPlayerSync.preview(espn_players)

      # Run the sync for real against prod
      EspnPlayerSync.run(espn_players, :prod)

      # Run against both prod and staging
      EspnPlayerSync.run(espn_players, :both)

  ## Exploration helpers

      # Fetch just the first page of players to inspect the data shape
      sample = EspnPlayerSync.fetch_sample(10)

      # Look at a single ESPN player's structure
      EspnPlayerSync.inspect_player(sample, 0)

      # Search ESPN players by name
      EspnPlayerSync.search(espn_players, "Ohtani")

      # Check DB players that are owned but have no playerDataId
      EspnPlayerSync.unclaimed_owned(:prod)

      # Check recent sync history
      EspnPlayerSync.sync_history()
  """

  @doc "Fetch all ESPN players from the API (paginated, raw maps)."
  def fetch_players(opts \\ []) do
    year = Keyword.get(opts, :year, Application.get_env(:trade_machine, :espn_season_year))
    sleep_ms = Keyword.get(opts, :sleep_ms, 5_000)
    limit = Keyword.get(opts, :limit, 100)

    IO.puts("Fetching all ESPN players for #{year} (limit=#{limit}, sleep=#{sleep_ms}ms)...")
    IO.puts("This will take a few minutes due to pagination + rate limit delays.\n")

    client = Client.new(year)
    {:ok, players} = Client.get_all_players(client, raw: true, limit: limit, sleep_ms: sleep_ms)

    IO.puts("\nFetched #{length(players)} ESPN players total.")
    players
  end

  @doc "Fetch a small sample of ESPN players (first page only)."
  def fetch_sample(count \\ 25) do
    year = Application.get_env(:trade_machine, :espn_season_year)
    IO.puts("Fetching sample of #{count} ESPN players for #{year}...")

    client = Client.new(year)

    filter = %{
      players: %{
        limit: count,
        offset: 0,
        sortPercOwned: %{sortAsc: false, sortPriority: 1}
      }
    }

    headers = [{"X-Fantasy-Filter", Jason.encode!(filter)}]

    case Req.get(client.req, url: "", params: [view: "kona_player_info"], headers: headers) do
      {:ok, %{status: 200, body: %{"players" => players}}} ->
        IO.puts("Got #{length(players)} players.")
        players

      {:ok, %{status: status, body: body}} ->
        IO.puts("Error: HTTP #{status}")
        IO.inspect(body, limit: 5)
        []

      {:error, reason} ->
        IO.puts("Request failed: #{inspect(reason)}")
        []
    end
  end

  @doc "Pretty-print a single ESPN player entry from a list."
  def inspect_player(espn_players, index \\ 0) do
    player = Enum.at(espn_players, index)

    if player do
      p = player["player"]
      team_abbrev = Constants.mlb_team_abbrev(p["proTeamId"])
      position = Constants.position(p["defaultPositionId"])

      IO.puts("""
      ── ESPN Player ##{index} ──
        ESPN ID:    #{player["id"]}
        Name:       #{p["fullName"]}
        MLB Team:   #{team_abbrev} (proTeamId=#{p["proTeamId"]})
        Position:   #{position} (defaultPositionId=#{p["defaultPositionId"]})
        Status:     #{player["status"]}
        On Team ID: #{player["onTeamId"]}
        Active:     #{p["active"]}
        Slots:      #{Constants.eligible_positions(p["eligibleSlots"] || [])}
      """)

      player
    else
      IO.puts("No player at index #{index}.")
      nil
    end
  end

  @doc "Search ESPN players by name (case-insensitive substring)."
  def search(espn_players, query) do
    q = String.downcase(query)

    results =
      Enum.filter(espn_players, fn ep ->
        name = get_in(ep, ["player", "fullName"]) || ""
        String.contains?(String.downcase(name), q)
      end)

    IO.puts("Found #{length(results)} ESPN players matching \"#{query}\":\n")

    Enum.each(results, fn ep ->
      p = ep["player"]
      team = Constants.mlb_team_abbrev(p["proTeamId"])
      pos = Constants.position(p["defaultPositionId"])

      IO.puts(
        "  #{ep["id"]} | #{p["fullName"]} | #{team} | #{pos} | status=#{ep["status"]} onTeam=#{ep["onTeamId"]}"
      )
    end)

    results
  end

  @doc """
  Preview the sync without writing to the database.

  Shows how many players would be updated, inserted, and skipped.
  """
  def preview(espn_players, env \\ :prod) do
    repo = repo_for(env)
    IO.puts("Preview sync against #{inspect(repo)}...\n")

    db_players = Players.get_syncable_players(repo)

    espn_by_id = Map.new(espn_players, fn ep -> {ep["id"], ep} end)

    matched_by_data_id =
      Enum.filter(db_players, fn p ->
        p.player_data_id != nil and Map.has_key?(espn_by_id, p.player_data_id)
      end)

    missing_from_espn =
      Enum.filter(db_players, fn p ->
        p.player_data_id != nil and not Map.has_key?(espn_by_id, p.player_data_id)
      end)

    unclaimed =
      Enum.filter(db_players, fn p ->
        p.player_data_id == nil and p.league == :major
      end)

    matched_espn_ids = MapSet.new(matched_by_data_id, & &1.player_data_id)

    new_espn =
      Enum.reject(espn_players, fn ep -> MapSet.member?(matched_espn_ids, ep["id"]) end)

    IO.puts("""
    ── Sync Preview ──
      DB players in scope:         #{length(db_players)}
      ESPN players fetched:        #{length(espn_players)}

    Phase 1 (match by playerDataId):
      Would update:                #{length(matched_by_data_id)}
      Missing from ESPN (retired): #{length(missing_from_espn)}

    Phase 2 (claim unclaimed):
      DB major leaguers w/o ID:    #{length(unclaimed)}
      (of those, owned):           #{Enum.count(unclaimed, & &1.leagueTeamId)}

    Phase 3 (new inserts):
      Unmatched ESPN players:      ~#{length(new_espn)} (upper bound, some may match in phase 2)
    """)

    if length(missing_from_espn) > 0 do
      IO.puts("Players missing from ESPN (first 10):")

      missing_from_espn
      |> Enum.take(10)
      |> Enum.each(fn p ->
        IO.puts("  #{p.player_data_id} | #{p.name} | #{p.mlb_team}")
      end)

      IO.puts("")
    end

    if length(unclaimed) > 0 do
      IO.puts("Unclaimed owned major leaguers (first 10):")

      unclaimed
      |> Enum.filter(& &1.leagueTeamId)
      |> Enum.take(10)
      |> Enum.each(fn p ->
        IO.puts("  #{p.name} | #{p.mlb_team} | team=#{p.leagueTeamId}")
      end)

      IO.puts("")
    end

    :ok
  end

  @doc """
  Run the actual sync.

  Acquires the SyncLock to prevent concurrent runs (same lock used by the
  Oban cron job). Returns `{:error, :already_running}` if another sync is
  in progress.

  ## Examples

      EspnPlayerSync.run(espn_players, :prod)
      EspnPlayerSync.run(espn_players, :staging)
      EspnPlayerSync.run(espn_players, :both)
      EspnPlayerSync.run(espn_players, :prod, skip_if_synced_within: 0)
  """
  def run(espn_players, env \\ :prod, opts \\ []) do
    case TradeMachine.SyncLock.acquire(:mlb_players_sync) do
      :acquired ->
        try do
          do_run(espn_players, env, opts)
        after
          TradeMachine.SyncLock.release(:mlb_players_sync)
        end

      {:already_running, acquired_at} ->
        IO.puts("⚠ Another MLB players sync is already running (since #{acquired_at}).")

        IO.puts(
          "  Use SyncLock.status() to inspect, or SyncLock.force_release(:mlb_players_sync) to override."
        )

        {:error, :already_running}
    end
  end

  defp do_run(espn_players, env, opts) do
    repos =
      case env do
        :both -> [TradeMachine.Repo.Production, TradeMachine.Repo.Staging]
        :staging -> [TradeMachine.Repo.Staging]
        _ -> [TradeMachine.Repo.Production]
      end

    for repo <- repos do
      IO.puts("Running sync against #{inspect(repo)}...")
      result = Players.sync_espn_player_data(espn_players, repo, opts)

      case result do
        {:ok, stats} ->
          IO.puts("  Updated:  #{stats.updated}")
          IO.puts("  Inserted: #{stats.inserted}")
          IO.puts("  Skipped:  #{stats.skipped}\n")

        {:error, reason} ->
          IO.puts("  ERROR: #{inspect(reason)}\n")
      end

      result
    end
  end

  @doc "Show DB players that are owned but have no playerDataId (candidates for phase 2)."
  def unclaimed_owned(env \\ :prod) do
    repo = repo_for(env)

    players =
      Player
      |> where(
        [p],
        p.league == :major and is_nil(p.player_data_id) and not is_nil(p.leagueTeamId)
      )
      |> select([p], %{
        id: p.id,
        name: p.name,
        mlb_team: p.mlb_team,
        league_team_id: p.leagueTeamId
      })
      |> repo.all()

    IO.puts("#{length(players)} owned major leaguers without playerDataId:\n")

    Enum.each(players, fn p ->
      IO.puts("  #{p.name} | #{p.mlb_team} | leagueTeam=#{p.league_team_id}")
    end)

    players
  end

  @doc "Show recent sync job execution history for mlb_players_sync."
  def sync_history(limit \\ 10) do
    repo = TradeMachine.Repo.Production

    history =
      TradeMachine.Data.SyncJobExecution
      |> where([s], s.job_type == :mlb_players_sync)
      |> order_by([s], desc: s.started_at)
      |> Ecto.Query.limit(^limit)
      |> repo.all()

    IO.puts("Last #{min(length(history), limit)} mlb_players_sync executions:\n")

    Enum.each(history, fn s ->
      duration =
        if s.completed_at && s.started_at do
          DateTime.diff(s.completed_at, s.started_at, :second)
        else
          "—"
        end

      IO.puts(
        "  #{s.status} | #{Calendar.strftime(s.started_at, "%Y-%m-%d %H:%M:%S")} | " <>
          "duration=#{duration}s | processed=#{s.records_processed || "—"} " <>
          "updated=#{s.records_updated || "—"} skipped=#{s.records_skipped || "—"}"
      )
    end)

    history
  end

  @doc "Check a specific DB player by name to see its sync state."
  def check_player(name, env \\ :prod) do
    repo = repo_for(env)

    players =
      Player
      |> where([p], p.name == ^name)
      |> select_merge([p], %{meta: p.meta})
      |> repo.all()

    Enum.each(players, fn p ->
      has_espn = p.meta && Map.has_key?(p.meta, "espnPlayer")

      IO.puts("""
      ── #{p.name} ──
        ID:            #{p.id}
        League:        #{p.league}
        MLB Team:      #{p.mlb_team}
        playerDataId:  #{p.player_data_id || "nil"}
        lastSyncedAt:  #{p.last_synced_at || "never"}
        leagueTeamId:  #{p.leagueTeamId || "nil"}
        Has ESPN meta: #{has_espn}
        Position:      #{get_in(p.meta || %{}, ["position"]) || "unknown"}
      """)
    end)

    players
  end

  defp repo_for(:staging), do: TradeMachine.Repo.Staging
  defp repo_for(_), do: TradeMachine.Repo.Production
end

IO.puts("\n✅ EspnPlayerSync helpers loaded. Type EspnPlayerSync. to see available functions.\n")

# defmodule StartupModule do
#  require Kernel.SpecialForms
#
#  def get_all_schema_modules() do
#    get_all_modules()
#    |> filter_and_return_schema_modules()
#    |> Enum.each(fn module ->
#      IO.inspect(module)
#      #      alias module
#    end)
#  end
#
#  defp get_all_modules() do
#    {:ok, all_modules} = :application.get_key(:trade_machine, :modules)
#
#    all_modules
#  end
#
#  defp filter_and_return_schema_modules(list_of_modules) do
#    list_of_modules
#    |> Enum.flat_map(fn module ->
#      case is_schema_module(Module.split(module)) do
#        true -> [module]
#        false -> []
#      end
#    end)
#  end
#
#  defp is_schema_module(["TradeMachine", "Data", _]), do: true
#  defp is_schema_module(_), do: false
# end
#
# StartupModule.get_all_schema_modules()
