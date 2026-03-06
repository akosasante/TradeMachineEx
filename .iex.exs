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

defmodule TradeMachine.Discord.EmbedTester do
  @moduledoc """
  Test different Discord embed formats for trade announcements.

  ## Usage

      # Test all formats at once (uses team names by default)
      TradeMachine.Discord.EmbedTester.test_all_formats()
      
      # Test with owner display names instead of team names
      TradeMachine.Discord.EmbedTester.test_all_formats(name_style: :owner_names)
      
      # Test with CSV names instead of team names
      TradeMachine.Discord.EmbedTester.test_all_formats(name_style: :csv_names)
      
      # Test individual format
      TradeMachine.Discord.EmbedTester.test_format_1()
      TradeMachine.Discord.EmbedTester.test_format_1(name_style: :owner_names)
      
      # Test against a specific channel
      TradeMachine.Discord.EmbedTester.test_all_formats(channel_id: 123456789)
      
  ## Name Style Options

  - `:team_names` (default) - "The Mad King" & "Birchmount Boyz"
  - `:owner_names` - "Ryan Neeson" & "Mikey"
  - `:csv_names` - Uses the csvName field from User table (one per team)
  """

  alias Nostrum.Api
  require Logger

  # Default test channel ID - override with channel_id: option
  @default_channel_id 993_941_280_184_864_928

  # ============================================================================
  # Public API
  # ============================================================================

  def test_all_formats(opts \\ []) do
    trade = build_sample_trade()

    Logger.info("Testing all Discord embed formats...")

    test_format("Option 1: Compact (Slack-like)", build_compact_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 2: Inline Fields (Side-by-side)", build_inline_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 3: Multiple Embeds (One per team)", build_multi_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 4: Emoji Style (Scannable)", build_emoji_embed(trade, opts), opts)
    :timer.sleep(2000)

    test_format("Option 5: Detailed (Polished)", build_detailed_embed(trade, opts), opts)

    Logger.info("All formats tested!")
  end

  def test_format_1(opts \\ []),
    do: test_single("Option 1: Compact", &build_compact_embed/2, opts)

  def test_format_2(opts \\ []),
    do: test_single("Option 2: Inline Fields", &build_inline_embed/2, opts)

  def test_format_3(opts \\ []),
    do: test_single("Option 3: Multiple Embeds", &build_multi_embed/2, opts)

  def test_format_4(opts \\ []),
    do: test_single("Option 4: Emoji Style", &build_emoji_embed/2, opts)

  def test_format_5(opts \\ []),
    do: test_single("Option 5: Detailed", &build_detailed_embed/2, opts)

  # ============================================================================
  # Option 1: Compact Embed (Most Slack-like)
  # ============================================================================

  defp build_compact_embed(trade, opts) do
    %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      description: """
      **#{format_date()}** | Trade requested by #{format_mentions(trade.creator.owners)}
      Trading with: #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
      Trade will be upheld after: <t:#{calculate_uphold_timestamp()}:F>
      """,
      color: 0x3498DB,
      fields: build_participant_fields(trade, opts),
      footer: %{
        text: "🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET"
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # ============================================================================
  # Option 2: Inline Fields (Side-by-side for 2-team trades)
  # ============================================================================

  defp build_inline_embed(trade, opts) do
    %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      description: """
      Trade submitted between **#{format_participant_name(trade.creator, opts)}** & **#{format_recipients(trade.recipients, opts)}**

      **#{format_date()}** | Requested by #{format_mentions(trade.creator.owners)}
      Trading with: #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
      Uphold time: <t:#{calculate_uphold_timestamp()}:F>
      """,
      color: 0x3498DB,
      fields: build_inline_fields(trade, opts),
      footer: %{
        text: "🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET"
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_inline_fields(trade, opts) do
    # For 2-team trades, set inline: true to show side-by-side
    inline = length(trade.participants) == 2

    Enum.map(trade.participants, fn participant ->
      %{
        name: "#{format_participant_name(participant, opts)} receives:",
        value: format_received_items(trade, participant),
        inline: inline
      }
    end)
  end

  # ============================================================================
  # Option 3: Multiple Embeds (One per team)
  # ============================================================================

  defp build_multi_embed(trade, opts) do
    header_embed = %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      description: """
      **#{format_date()}** | Trade requested by #{format_mentions(trade.creator.owners)}
      Trading with: #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
      Trade will be upheld after: <t:#{calculate_uphold_timestamp()}:F>
      """,
      color: 0x3498DB,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    participant_embeds =
      Enum.map(trade.participants, fn participant ->
        %{
          title: "#{format_participant_name(participant, opts)} receives:",
          description: format_received_items(trade, participant),
          color: get_team_color(participant.team)
        }
      end)

    footer_embed = %{
      description: "🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET",
      color: 0x95A5A6
    }

    [header_embed] ++ participant_embeds ++ [footer_embed]
  end

  # ============================================================================
  # Option 4: Emoji Style (More scannable)
  # ============================================================================

  defp build_emoji_embed(trade, opts) do
    %{
      title: "🔊  A Trade Has Been Submitted  🔊",
      color: 0x3498DB,
      fields:
        [
          %{
            name: "📅 Date & Time",
            value: """
            **#{format_date()}**
            Uphold time: <t:#{calculate_uphold_timestamp()}:F>
            """,
            inline: false
          },
          %{
            name: "👥 Participants",
            value: """
            **Requested by:** #{format_mentions(trade.creator.owners)}
            **Trading with:** #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
            """,
            inline: false
          }
        ] ++
          build_participant_fields_with_emoji(trade, opts) ++
          [
            %{
              name: "🔗 Submit Your Trades",
              value: "Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET",
              inline: false
            }
          ],
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_participant_fields_with_emoji(trade, opts) do
    Enum.map(trade.participants, fn participant ->
      %{
        name: "🎁 #{format_participant_name(participant, opts)} receives:",
        value: format_received_items_with_emoji(trade, participant),
        inline: false
      }
    end)
  end

  # ============================================================================
  # Option 5: Detailed with Author and Thumbnail
  # ============================================================================

  defp build_detailed_embed(trade, opts) do
    %{
      author: %{
        name: "FlexFoxFantasy TradeMachine",
        url: "https://trades.flexfoxfantasy.com"
        # icon_url: "https://your-logo-url.com/logo.png"  # Uncomment if you have a logo
      },
      title: "🔊  A Trade Has Been Submitted  🔊",
      # url: "https://trades.flexfoxfantasy.com/trades/#{trade.id}",  # Uncomment for deep linking
      description: """
      Trade submitted between **#{format_participant_name(trade.creator, opts)}** & **#{format_recipients(trade.recipients, opts)}**
      """,
      color: 0x3498DB,
      fields:
        [
          %{
            name: "📋 Trade Details",
            value: """
            **Requested by:** #{format_mentions(trade.creator.owners)}
            **Trading with:** #{format_mentions(trade.recipients |> Enum.flat_map(& &1.owners))}
            **Date:** #{format_date()}
            **Uphold after:** <t:#{calculate_uphold_timestamp()}:F>
            """,
            inline: false
          }
        ] ++ build_participant_fields(trade, opts),
      footer: %{
        text: "Submit trades by 11:00PM ET"
        # icon_url: "https://your-icon-url.com/clock.png"  # Optional
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # ============================================================================
  # Helper Functions - Field Builders
  # ============================================================================

  defp build_participant_fields(trade, opts) do
    Enum.map(trade.participants, fn participant ->
      %{
        name: "#{format_participant_name(participant, opts)} receives:",
        value: format_received_items(trade, participant),
        inline: false
      }
    end)
  end

  # ============================================================================
  # Helper Functions - Name Formatting
  # ============================================================================

  defp format_participant_name(participant, opts) do
    name_style = Keyword.get(opts, :name_style, :team_names)

    case name_style do
      :team_names ->
        participant.team.name

      :owner_names ->
        participant.team.owners
        |> Enum.map(& &1.display_name)
        |> Enum.join(" & ")

      :csv_names ->
        # Find the first owner with a csvName (should only be one per team)
        participant.team.owners
        |> Enum.find_value(fn owner -> owner.csv_name end)
        |> case do
          # Fallback to team name
          nil -> participant.team.name
          csv_name -> csv_name
        end
    end
  end

  defp format_recipients(recipients, opts) do
    Enum.map_join(recipients, " & ", &format_participant_name(&1, opts))
  end

  # ============================================================================
  # Helper Functions - Item Formatting
  # ============================================================================

  defp format_received_items(_trade, participant) do
    items = participant.received_items

    # Separate majors and minors
    {majors, minors} =
      Enum.split_with(items, fn item ->
        item.type == :player && item.league == "Majors"
      end)

    # Format majors
    majors_text =
      majors
      |> Enum.map(fn item ->
        case item.type do
          :player ->
            "• **#{item.name}** (#{item.position} - Majors - #{item.team})"

          :pick ->
            "• **#{item.original_owner}'s** #{item.round} round #{item.league} pick"
        end
      end)
      |> Enum.join("\n")

    # Format minors/picks
    minors_text =
      minors
      |> Enum.map(fn item ->
        case item.type do
          :player when is_nil(item.position) ->
            "• **#{item.name}** (undefined - undefined Minors - undefined)"

          :player ->
            "• **#{item.name}** (#{item.position} - #{item.league_level} Minors - #{item.team})"

          :pick ->
            "• **#{item.original_owner}'s** #{item.round} round #{item.league} pick"
        end
      end)
      |> Enum.join("\n")

    # Combine with spacing
    [majors_text, minors_text]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> case do
      "" -> "_No items_"
      text -> text
    end
  end

  defp format_received_items_with_emoji(_trade, participant) do
    items = participant.received_items

    items
    |> Enum.map(fn item ->
      emoji =
        case item.type do
          :player when item.league == "Majors" -> "⚾"
          :player -> "🌱"
          :pick -> "🎟️"
        end

      case item.type do
        :player when item.league == "Majors" ->
          "#{emoji} **#{item.name}** (#{item.position} - Majors - #{item.team})"

        :player when is_nil(item.position) ->
          "#{emoji} **#{item.name}** (undefined - undefined Minors - undefined)"

        :player ->
          "#{emoji} **#{item.name}** (#{item.position} - #{item.league_level} Minors - #{item.team})"

        :pick ->
          "#{emoji} **#{item.original_owner}'s** #{item.round} round #{item.league} pick"
      end
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "_No items_"
      text -> text
    end
  end

  defp format_date do
    now = DateTime.utc_now()
    Calendar.strftime(now, "%a %b %-d %Y")
  end

  defp format_mentions(owners) do
    mentions =
      owners
      |> Enum.filter(& &1.discord_user_id)
      |> Enum.map(&"<@#{&1.discord_user_id}>")
      |> Enum.join(", ")

    case mentions do
      "" ->
        # Fallback to display names if no Discord IDs
        owners
        |> Enum.map(&"@#{&1.display_name}")
        |> Enum.join(", ")

      mentions ->
        mentions
    end
  end

  defp calculate_uphold_timestamp do
    # Simplified: 24 hours from now
    # In production, use your actual uphold time calculation
    DateTime.utc_now()
    |> DateTime.add(86400, :second)
    |> DateTime.to_unix()
  end

  defp get_team_color(team) do
    # Assign different colors to different teams
    # You could store these in your database or use a hash function
    colors = [
      # Red
      0xE74C3C,
      # Blue
      0x3498DB,
      # Green
      0x2ECC71,
      # Orange
      0xF39C12,
      # Purple
      0x9B59B6,
      # Turquoise
      0x1ABC9C,
      # Carrot
      0xE67E22,
      # Dark gray
      0x34495E
    ]

    # Simple hash based on team name
    index = :erlang.phash2(team.name, length(colors))
    Enum.at(colors, index)
  end

  # ============================================================================
  # Sample Data
  # ============================================================================

  defp build_sample_trade do
    # Based on your screenshot, enhanced with draft picks of each level
    %{
      id: "test-trade-id",
      creator: %{
        name: "The Mad King",
        team: %{name: "The Mad King"},
        owners: [
          %{display_name: "Ryan Neeson", discord_user_id: nil, csv_name: "Ryan"}
        ]
      },
      recipients: [
        %{
          name: "Birchmount Boyz",
          team: %{name: "Birchmount Boyz"},
          owners: [%{display_name: "Mikey", discord_user_id: nil, csv_name: "Mikey"}]
        },
        %{
          name: "Team James",
          team: %{name: "Team James"},
          owners: [%{display_name: "James", discord_user_id: nil, csv_name: "James"}]
        }
      ],
      participants: [
        %{
          team: %{
            name: "The Mad King",
            owners: [%{display_name: "Ryan Neeson", discord_user_id: nil, csv_name: "Ryan"}]
          },
          received_items: [
            %{
              type: :player,
              name: "Ketel Marte",
              position: "2B",
              league: "Majors",
              team: "ARI"
            },
            %{
              type: :pick,
              original_owner: "Birchmount Boyz",
              round: "2nd",
              league: "Major League",
              season: 2026
            },
            %{
              type: :pick,
              original_owner: "Team James",
              round: "3rd",
              league: "High Minors",
              season: 2026
            }
          ]
        },
        %{
          team: %{
            name: "Birchmount Boyz",
            owners: [%{display_name: "Mikey", discord_user_id: nil, csv_name: "Mikey"}]
          },
          received_items: [
            %{
              type: :player,
              name: "George Kirby",
              position: "SP",
              league: "Majors",
              team: "SEA"
            },
            %{
              type: :player,
              name: "Patrick Forbes",
              position: nil,
              league: "Minors",
              league_level: "undefined",
              team: nil
            },
            %{
              type: :pick,
              original_owner: "The Mad King",
              round: "1st",
              league: "Low Minors",
              season: 2026
            }
          ]
        },
        %{
          team: %{
            name: "Team James",
            owners: [%{display_name: "James", discord_user_id: nil, csv_name: "James"}]
          },
          received_items: [
            %{
              type: :player,
              name: "Zachary Root",
              position: nil,
              league: "Minors",
              league_level: "undefined",
              team: nil
            },
            %{
              type: :pick,
              original_owner: "Birchmount Boyz",
              round: "4th",
              league: "Major League",
              season: 2027
            }
          ]
        }
      ]
    }
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp test_format(name, embed_or_embeds, opts) do
    embeds = if is_list(embed_or_embeds), do: embed_or_embeds, else: [embed_or_embeds]
    channel_id = Keyword.get(opts, :channel_id, @default_channel_id)

    Logger.info("Sending: #{name}")

    case Api.create_message(channel_id,
           content: "**#{name}**",
           embeds: embeds
         ) do
      {:ok, _message} ->
        Logger.info("✓ #{name} sent successfully")
        :ok

      {:error, reason} ->
        Logger.error("✗ #{name} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_single(name, builder_fn, opts) do
    trade = build_sample_trade()
    embed_or_embeds = builder_fn.(trade, opts)
    test_format(name, embed_or_embeds, opts)
  end
end

IO.puts(
  "✅ TradeMachine.Discord.EmbedTester loaded. Type TradeMachine.Discord.EmbedTester. to see available functions.\n"
)

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
