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

defmodule MinorLeagueReconciliation do
  @moduledoc """
  IEx helpers for running the minor league ESPN reconciliation script.

  This script:
  1. Nullifies `playerDataId` for all minor league players
  2. Searches ESPN for each minor leaguer to find their ESPN ID
  3. Auto-applies exact matches, logs fuzzy/ambiguous/no-match for review

  ## Quick start

      # Dry run first (no DB changes, just see what would happen)
      MinorLeagueReconciliation.run(:prod, dry_run: true)

      # Run for real against prod
      MinorLeagueReconciliation.run(:prod)

      # Run against staging
      MinorLeagueReconciliation.run(:staging)

      # Run against both
      MinorLeagueReconciliation.run(:both)

  ## Options

      # Skip phase 1 (don't nullify, useful for re-runs)
      MinorLeagueReconciliation.run(:prod, skip_phase1: true)

      # Faster requests (lower delay, higher rate-limit risk)
      MinorLeagueReconciliation.run(:prod, delay_ms: 1000)

  ## After running

      # Review reports in priv/scripts/output/
      # Then run the regular ESPN sync to backfill full espnPlayer data:
      espn_players = EspnPlayerSync.fetch_players()
      EspnPlayerSync.run(espn_players, :prod, skip_if_synced_within: 0)

  ## Manual search

      # Test the ESPN search for a single player
      MinorLeagueReconciliation.search("Pedro Pineda")
  """

  alias TradeMachine.ESPN.Search

  @doc """
  Run the reconciliation against the given environment(s).

  ## Options
    - `:dry_run`     — preview only, no DB writes (default: false)
    - `:delay_ms`    — ms between ESPN API calls (default: 1500)
    - `:skip_phase1` — skip nullifying playerDataId (default: false)
    - `:output_dir`  — where to write CSV reports (default: "priv/scripts/output")
  """
  def run(env, opts \\ []) do
    repos = repos_for(env)

    for repo <- repos do
      IO.puts("\n" <> String.duplicate("─", 60))
      IO.puts("Running reconciliation against #{inspect(repo)}")
      IO.puts(String.duplicate("─", 60) <> "\n")

      TradeMachine.MinorLeagueReconciliation.run(repo, opts)
    end
  end

  @doc "Search ESPN for a player by name (for manual testing)."
  def search(name) do
    IO.puts("Searching ESPN for \"#{name}\"...\n")

    case Search.search_mlb_player(name) do
      {:ok, results} ->
        if results == [] do
          IO.puts("  No MLB baseball players found.")
        else
          Enum.each(results, fn r ->
            IO.puts(
              "  #{r.espn_id || "?"} | #{r.name} | #{r.team || "?"} | " <>
                "#{r.league_slug || "?"} | #{r.description || "?"}"
            )
          end)
        end

        IO.puts("\n  #{length(results)} result(s).\n")
        results

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
        []
    end
  end

  @doc "Show current minor league players and their playerDataId status."
  def status(env \\ :prod) do
    repo = List.first(repos_for(env))

    import Ecto.Query

    total =
      TradeMachine.Data.Player
      |> where([p], p.league == :minor)
      |> repo.aggregate(:count)

    with_id =
      TradeMachine.Data.Player
      |> where([p], p.league == :minor and not is_nil(p.player_data_id))
      |> repo.aggregate(:count)

    without_id =
      TradeMachine.Data.Player
      |> where([p], p.league == :minor and is_nil(p.player_data_id))
      |> repo.aggregate(:count)

    IO.puts("""

    Minor League Player Status (#{inspect(repo)})
    ─────────────────────────────────────
      Total minor leaguers:    #{total}
      With playerDataId:       #{with_id}
      Without playerDataId:    #{without_id}
    """)
  end

  defp repos_for(:both), do: [TradeMachine.Repo.Production, TradeMachine.Repo.Staging]
  defp repos_for(:staging), do: [TradeMachine.Repo.Staging]
  defp repos_for(_), do: [TradeMachine.Repo.Production]
end

IO.puts(
  "✅ MinorLeagueReconciliation helpers loaded. Type MinorLeagueReconciliation. to see available functions.\n"
)

defmodule MinorLeagueSync do
  @moduledoc """
  IEx helpers for testing the minor league sheet sync locally.

  ## Quick start

      # Fetch CSV rows from the sheet
      {:ok, rows} = MinorLeagueSync.fetch()

      # Parse into player maps
      players = MinorLeagueSync.parse()

      # Preview a few parsed players
      MinorLeagueSync.preview()

      # Run the sync against production
      MinorLeagueSync.run(:prod)

      # Run against both repos
      MinorLeagueSync.run(:both)

      # Check sync history
      MinorLeagueSync.sync_history()
  """

  alias TradeMachine.MinorLeagues.{SheetFetcher, Parser, Sync}

  @doc "Fetch raw CSV rows from the minor league sheet."
  def fetch do
    SheetFetcher.fetch_from_config()
  end

  @doc "Fetch and parse the sheet into player maps."
  def parse do
    {:ok, rows} = fetch()
    Parser.parse(rows)
  end

  @doc "Preview the first N parsed players (default 20)."
  def preview(count \\ 20) do
    players = parse()
    IO.puts("Parsed #{length(players)} players total. Showing first #{count}:\n")

    players
    |> Enum.take(count)
    |> Enum.each(fn p ->
      IO.puts(
        "  #{p.name} | #{p.league_level} | #{p.position} | #{p.mlb_team} | owner=#{p.owner_csv_name}"
      )
    end)

    owners = players |> Enum.map(& &1.owner_csv_name) |> Enum.uniq() |> Enum.sort()
    IO.puts("\nOwners found (#{length(owners)}): #{Enum.join(owners, ", ")}")

    players
  end

  @doc "Show owner name mapping: which sheet names resolve to teams."
  def check_owners(env \\ :prod) do
    repo = repo_for(env)
    owner_map = Sync.build_owner_map(repo)
    players = parse()

    sheet_owners = players |> Enum.map(& &1.owner_csv_name) |> Enum.uniq() |> Enum.sort()

    IO.puts("Owner mapping (#{inspect(repo)}):\n")

    Enum.each(sheet_owners, fn name ->
      case Map.get(owner_map, name) do
        nil -> IO.puts("  ✗ #{name} → NOT FOUND")
        team_id -> IO.puts("  ✓ #{name} → #{team_id}")
      end
    end)

    unmatched = Enum.reject(sheet_owners, &Map.has_key?(owner_map, &1))

    if unmatched != [] do
      IO.puts("\n⚠ #{length(unmatched)} owner(s) could not be resolved: #{inspect(unmatched)}")
    end

    owner_map
  end

  @doc """
  Run the sync against the given environment.

  ## Examples

      MinorLeagueSync.run(:prod)
      MinorLeagueSync.run(:staging)
      MinorLeagueSync.run(:both)
  """
  def run(env \\ :prod) do
    case TradeMachine.SyncLock.acquire(:minors_sync) do
      :acquired ->
        try do
          do_run(env)
        after
          TradeMachine.SyncLock.release(:minors_sync)
        end

      {:already_running, acquired_at} ->
        IO.puts(
          "Another minor league sync is already running (since #{acquired_at}).\n" <>
            "Use SyncLock.force_release(:minors_sync) to override."
        )

        {:error, :already_running}
    end
  end

  defp do_run(env) do
    players = parse()
    repos = repos_for(env)

    for repo <- repos do
      IO.puts("Syncing #{length(players)} players against #{inspect(repo)}...")

      case Sync.sync_from_sheet(players, repo) do
        {:ok, stats} ->
          IO.puts("  Matched:  #{stats.matched}")
          IO.puts("  Inserted: #{stats.inserted}")
          IO.puts("  Cleared:  #{stats.cleared}")
          IO.puts("  Skipped:  #{stats.skipped_no_owner}\n")
          {:ok, stats}

        {:error, reason} ->
          IO.puts("  ERROR: #{inspect(reason)}\n")
          {:error, reason}
      end
    end
  end

  @doc "Show recent sync job execution history for minors_sync."
  def sync_history(limit \\ 10) do
    import Ecto.Query

    repo = TradeMachine.Repo.Production

    history =
      TradeMachine.Data.SyncJobExecution
      |> where([s], s.job_type == :minors_sync)
      |> order_by([s], desc: s.started_at)
      |> Ecto.Query.limit(^limit)
      |> repo.all()

    IO.puts("Last #{min(length(history), limit)} minors_sync executions:\n")

    Enum.each(history, fn s ->
      duration =
        if s.completed_at && s.started_at do
          DateTime.diff(s.completed_at, s.started_at, :second)
        else
          "-"
        end

      IO.puts(
        "  #{s.status} | #{Calendar.strftime(s.started_at, "%Y-%m-%d %H:%M:%S")} | " <>
          "duration=#{duration}s | processed=#{s.records_processed || "-"} " <>
          "updated=#{s.records_updated || "-"} skipped=#{s.records_skipped || "-"}"
      )
    end)

    history
  end

  defp repo_for(:staging), do: TradeMachine.Repo.Staging
  defp repo_for(_), do: TradeMachine.Repo.Production

  defp repos_for(:both), do: [TradeMachine.Repo.Production, TradeMachine.Repo.Staging]
  defp repos_for(:staging), do: [TradeMachine.Repo.Staging]
  defp repos_for(_), do: [TradeMachine.Repo.Production]
end

IO.puts("✅ MinorLeagueSync helpers loaded. Type MinorLeagueSync. to see available functions.\n")

defmodule DraftPicksSync do
  @moduledoc """
  IEx helpers for prototyping and testing the draft picks sheet sync.

  The parsing logic here is a prototype — it will live in
  `TradeMachine.DraftPicks.{Parser,Sync}` once the job is built. Use this
  module to validate the CSV structure and owner resolution before
  implementing the real modules.

  ## Quick start

      # Fetch raw CSV rows and inspect the structure
      {:ok, rows} = DraftPicksSync.fetch()
      DraftPicksSync.inspect_rows(rows, 0, 25)  # rows 0-24 (group 1)
      DraftPicksSync.inspect_rows(rows, 25, 20) # rows 25-44 (group 2)

      # Parse into pick maps and validate expected counts
      picks = DraftPicksSync.parse()
      DraftPicksSync.validate(picks)

      # Preview all picks for a specific owner
      DraftPicksSync.preview_owner(picks, "Flex")

      # Verify CSV names resolve to team IDs in the DB
      DraftPicksSync.check_owners()

      # Check what the current season would be calculated as
      DraftPicksSync.currt_season()

      # Check the current DB state of draft_pick table
      DraftPicksSync.db_state()

      # Sync history (once the job module exists)
      DraftPicksSync.sync_history()
  """

  @sheet_id "1jxtRmrwK6dbMQTS-PDn8l6hDHG0AlPYVtcVyxngG34U"
  @gid "142978697"
  @columns_per_owner 7
  @owners_per_group 5
  @total_columns @columns_per_owner * @owners_per_group
  # 30 columns total
  @picks_per_group 17
  # 10 ML + 2 HM + 5 LM

  @doc "Fetch raw CSV rows from the draft picks sheet tab."
  def fetch(sheet_id \\ @sheet_id, gid \\ @gid) do
    url = "https://docs.google.com/spreadsheets/d/#{sheet_id}/export?format=csv&gid=#{gid}"

    case Req.get(url, redirect_log_level: false) do
      {:ok, %{status: 200, body: rows}} when is_list(rows) ->
        IO.puts("Fetched #{length(rows)} rows.")
        {:ok, rows}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        IO.puts("Warning: CSV auto-decode did not trigger; got binary body.")
        IO.puts(String.slice(body, 0, 300))
        {:error, :unexpected_binary_body}

      {:ok, %{status: status}} ->
        IO.puts("HTTP #{status}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Inspect raw CSV rows within a range to understand the sheet structure.

  Shows the first 3 values of each owner chunk (Round, OrigOwner, OVR)
  separated by │. Useful for verifying group boundaries and cleared picks.
  """
  def inspect_rows(rows \\ nil, from \\ 0, count \\ 20) do
    rows = rows || elem(fetch(), 1)

    rows
    |> Enum.slice(from, count)
    |> Enum.with_index(from)
    |> Enum.each(fn {row, i} ->
      padded = pad_row(row, @total_columns)
      chunks = Enum.chunk_every(padded, @columns_per_owner)

      formatted =
        Enum.map_join(chunks, "  │  ", fn chunk ->
          "[#{chunk |> Enum.take(3) |> Enum.join(", ")}]"
        end)

      IO.puts("  Row #{String.pad_leading(to_string(i), 3)}: #{formatted}")
    end)

    :ok
  end

  @doc "Fetch and parse all picks into structured maps."
  def parse do
    {:ok, rows} = fetch()
    do_parse(rows)
  end

  def parse(rows), do: do_parse(rows)

  @doc """
  Validate parsed picks against expected totals.

  Expected: 200 :majors + 40 :high + 100 :low = 340 total
  """
  def validate(picks \\ nil) do
    picks = picks || parse()

    by_type = Enum.group_by(picks, & &1.type)
    majors = Map.get(by_type, :majors, [])
    high = Map.get(by_type, :high, [])
    low = Map.get(by_type, :low, [])

    majors_ok = length(majors) == 200
    high_ok = length(high) == 40
    low_ok = length(low) == 100
    total_ok = length(picks) == 340

    IO.puts("""
    ── Draft Picks Parse Validation ──

    Counts by type:
      :majors  #{length(majors)} (expected 200)  #{if majors_ok, do: "✓", else: "✗ MISMATCH"}
      :high    #{length(high)} (expected 40)   #{if high_ok, do: "✓", else: "✗ MISMATCH"}
      :low     #{length(low)} (expected 100)  #{if low_ok, do: "✓", else: "✗ MISMATCH"}
      TOTAL    #{length(picks)} (expected 340) #{if total_ok, do: "✓", else: "✗ MISMATCH"}

    Distinct current owners: #{picks |> Enum.map(& &1.current_owner_csv) |> Enum.uniq() |> length()}
    Distinct original owners: #{picks |> Enum.map(& &1.original_owner_csv) |> Enum.uniq() |> length()}
    """)

    unless total_ok do
      IO.puts("Per-owner breakdown (current owner):")

      picks
      |> Enum.group_by(& &1.current_owner_csv)
      |> Enum.sort_by(fn {owner, _} -> owner end)
      |> Enum.each(fn {owner, owner_picks} ->
        by_t = Enum.group_by(owner_picks, & &1.type)
        ml = length(Map.get(by_t, :majors, []))
        hm = length(Map.get(by_t, :high, []))
        lm = length(Map.get(by_t, :low, []))
        total = ml + hm + lm
        flag = if total == 17, do: "✓", else: "✗ (expected 17)"

        IO.puts(
          "  #{String.pad_trailing(owner, 15)} ML=#{ml} HM=#{hm} LM=#{lm}  total=#{total}  #{flag}"
        )
      end)
    end

    picks
  end

  @doc "Preview all picks for a specific owner CSV name."
  def preview_owner(picks \\ nil, owner_name) do
    picks = picks || parse()
    owner_picks = Enum.filter(picks, &(&1.current_owner_csv == owner_name))
    by_type = Enum.group_by(owner_picks, & &1.type)

    IO.puts("Picks currently owned by \"#{owner_name}\" (#{length(owner_picks)} total):\n")

    [:majors, :high, :low]
    |> Enum.each(fn type ->
      type_picks = Map.get(by_type, type, [])

      if type_picks != [] do
        IO.puts("  #{type} (#{length(type_picks)}):")

        Enum.each(type_picks, fn p ->
          traded =
            if p.current_owner_csv != p.original_owner_csv,
              do: "  ← traded from #{p.original_owner_csv}",
              else: ""

          IO.puts(
            "    round=#{p.round}  ovr=#{p.pick_number}  orig=#{p.original_owner_csv}#{traded}"
          )
        end)
      end
    end)

    owner_picks
  end

  @doc """
  Check that all CSV owner names in the sheet resolve to team IDs in the DB.

  Checks both current_owner_csv and original_owner_csv fields.
  """
  def check_owners(env \\ :prod) do
    repo = repo_for(env)
    picks = parse()

    owner_map =
      TradeMachine.Data.User
      |> where([u], not is_nil(u.csv_name) and not is_nil(u.teamId))
      |> select([u], {u.csv_name, u.teamId})
      |> repo.all()
      |> Map.new()

    all_csv_names =
      (Enum.map(picks, & &1.current_owner_csv) ++ Enum.map(picks, & &1.original_owner_csv))
      |> Enum.uniq()
      |> Enum.reject(&(&1 == ""))
      |> Enum.sort()

    IO.puts("Owner CSV name → team ID resolution (#{inspect(repo)}):\n")

    Enum.each(all_csv_names, fn name ->
      case Map.get(owner_map, name) do
        nil -> IO.puts("  ✗  #{name}")
        team_id -> IO.puts("  ✓  #{String.pad_trailing(name, 15)} → #{team_id}")
      end
    end)

    unmatched = Enum.reject(all_csv_names, &Map.has_key?(owner_map, &1))

    if unmatched != [] do
      IO.puts("\n⚠ #{length(unmatched)} name(s) NOT resolved: #{inspect(unmatched)}")
    else
      IO.puts("\n✓ All #{length(all_csv_names)} names resolved successfully.")
    end

    owner_map
  end

  @doc "Show current DB state of the draft_pick table."
  def db_state(env \\ :prod) do
    repo = repo_for(env)

    counts =
      TradeMachine.Data.DraftPick
      |> group_by([d], d.type)
      |> select([d], {d.type, count(d.id)})
      |> repo.all()
      |> Map.new()

    total = Enum.sum(Map.values(counts))

    IO.puts("""
    Draft Pick DB State (#{inspect(repo)}):
      :majors  #{Map.get(counts, :majors, 0)} (expected 200)
      :high    #{Map.get(counts, :high, 0)} (expected 40)
      :low     #{Map.get(counts, :low, 0)} (expected 100)
      TOTAL    #{total} (expected 340)
    """)

    counts
  end

  @doc """
  Show what the current draft season would be calculated as.

  Season = current year if today >= March 25, else prior year.
  Can be overridden with DRAFT_PICKS_SEASON env var.
  """
  def current_season do
    override = System.get_env("DRAFT_PICKS_SEASON")

    season =
      if override do
        String.to_integer(override)
      else
        today = Date.utc_today()

        if today.month > 3 or (today.month == 3 and today.day >= 25),
          do: today.year,
          else: today.year - 1
      end

    source = if override, do: "DRAFT_PICKS_SEASON override", else: "calculated"
    IO.puts("Current draft season: #{season}  (#{source}, today=#{Date.utc_today()})")
    season
  end

  @doc "Show recent sync history for draft_picks_sync."
  def sync_history(limit \\ 10) do
    repo = TradeMachine.Repo.Production

    history =
      TradeMachine.Data.SyncJobExecution
      |> where([s], s.job_type == :draft_picks_sync)
      |> order_by([s], desc: s.started_at)
      |> limit(^limit)
      |> repo.all()

    IO.puts("Last #{min(length(history), limit)} draft_picks_sync executions:\n")

    Enum.each(history, fn s ->
      duration =
        if s.completed_at && s.started_at,
          do: DateTime.diff(s.completed_at, s.started_at, :second),
          else: "-"

      IO.puts(
        "  #{s.status} | #{Calendar.strftime(s.started_at, "%Y-%m-%d %H:%M:%S")} | " <>
          "duration=#{duration}s | processed=#{s.records_processed || "-"} " <>
          "updated=#{s.records_updated || "-"} skipped=#{s.records_skipped || "-"}"
      )
    end)

    history
  end

  # ---------------------------------------------------------------------------
  # Prototype parsing logic (will live in TradeMachine.DraftPicks.Parser)
  # ---------------------------------------------------------------------------
  #
  # State machine:
  #   :scanning    → looking for a group owner header row
  #   :saw_owners  → captured owner names, waiting for the "Round" column header
  #   :in_picks    → reading pick rows (0..16), then back to :scanning
  #
  # Why a state machine?  Cleared picks have the team name in the Round column
  # (e.g. "Flex | 0 | Newton | -8 | ..."), which looks like an owner header
  # row if we try to classify rows without context. By tracking state, we know
  # that once we're in :in_picks any non-numeric Round column is just a
  # cleared pick (skipped via the Decimal.parse guard).

  defp do_parse(rows) do
    rows
    |> Enum.reduce(
      %{state: :scanning, current_owners: [], pick_row_index: 0, picks: []},
      fn row, acc ->
        padded = pad_row(row, @total_columns)
        chunks = Enum.chunk_every(padded, @columns_per_owner)
        first_cell = padded |> List.first("") |> String.trim()

        case acc.state do
          :scanning ->
            cond do
              skip_row?(first_cell) ->
                acc

              first_cell == "Round" ->
                acc

              true ->
                %{
                  acc
                  | state: :saw_owners,
                    current_owners: extract_owners(chunks),
                    pick_row_index: 0
                }
            end

          :saw_owners ->
            cond do
              first_cell == "Round" ->
                %{acc | state: :in_picks}

              skip_row?(first_cell) ->
                acc

              true ->
                # Groups 2-4: pick rows appear directly without a "Round" header row
                picks = extract_picks(chunks, acc.current_owners, 0)
                new_index = 1
                new_state = if new_index >= @picks_per_group, do: :scanning, else: :in_picks
                %{acc | state: new_state, picks: acc.picks ++ picks, pick_row_index: new_index}
            end

          :in_picks ->
            picks = extract_picks(chunks, acc.current_owners, acc.pick_row_index)
            new_index = acc.pick_row_index + 1
            new_state = if new_index >= @picks_per_group, do: :scanning, else: :in_picks
            %{acc | picks: acc.picks ++ picks, pick_row_index: new_index, state: new_state}
        end
      end
    )
    |> Map.get(:picks)
  end

  defp skip_row?(cell) do
    cell == "" or
      cell == "Draft Picks" or
      String.starts_with?(cell, "GREY") or
      String.starts_with?(cell, "BLUE") or
      String.starts_with?(cell, "RED")
  end

  defp extract_owners(chunks) do
    chunks
    |> Enum.take(@owners_per_group)
    |> Enum.map(fn chunk -> chunk |> List.first("") |> String.trim() end)
  end

  defp extract_picks(chunks, current_owners, pick_row_index) do
    type = pick_type(pick_row_index)

    chunks
    |> Enum.take(@owners_per_group)
    |> Enum.with_index()
    |> Enum.flat_map(fn {chunk, owner_idx} ->
      current_owner = Enum.at(current_owners, owner_idx, "")
      round_str = chunk |> Enum.at(0, "") |> String.trim()
      orig_owner = chunk |> Enum.at(1, "") |> String.trim()
      ovr_str = chunk |> Enum.at(3, "") |> String.trim()

      with {round, _} <- Decimal.parse(round_str),
           :gt <- Decimal.compare(round, Decimal.new(0)),
           {ovr, _} <- Integer.parse(ovr_str),
           true <- ovr > 0,
           false <- orig_owner == "" do
        [
          %{
            type: type,
            round: round,
            original_owner_csv: orig_owner,
            current_owner_csv: current_owner,
            pick_number: ovr
          }
        ]
      else
        _ -> []
      end
    end)
  end

  # row index within the group (0-indexed)
  defp pick_type(i) when i in 0..9, do: :majors
  defp pick_type(i) when i in 10..11, do: :high
  defp pick_type(i) when i in 12..16, do: :low
  defp pick_type(_), do: :unknown

  defp pad_row(row, expected) when length(row) >= expected, do: row
  defp pad_row(row, expected), do: row ++ List.duplicate("", expected - length(row))

  defp repo_for(:staging), do: TradeMachine.Repo.Staging
  defp repo_for(_), do: TradeMachine.Repo.Production
end

IO.puts("✅ DraftPicksSync helpers loaded. Type DraftPicksSync. to see available functions.\n")

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
