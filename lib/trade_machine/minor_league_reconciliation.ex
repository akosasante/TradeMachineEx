# credo:disable-for-this-file Credo.Check.Refactor.IoPuts
defmodule TradeMachine.MinorLeagueReconciliation do
  @moduledoc """
  One-time reconciliation script to assign ESPN IDs to minor league players.

  **Phase 1** — Nullifies `playerDataId` for all minor league players in the
  given repo, clearing out stale MLB API IDs from the defunct data source.

  **Phase 2** — Searches ESPN's public search API for each minor leaguer and
  classifies the result:

    - `:exact`      — single MLB result with exact name match → auto-applied
    - `:exact_team` — multiple exact name matches, disambiguated by MLB team → auto-applied
    - `:fuzzy`      — closest name has Jaro–Winkler score ≥ 0.85 → logged for review
    - `:ambiguous`  — multiple exact name matches, can't disambiguate → logged for review
    - `:no_match`   — no MLB baseball players returned → logged for review
    - `:error`      — API call failed → logged

  For `:exact` and `:exact_team` matches, the script updates:
    - `playerDataId` → ESPN player ID (integer)
    - `meta` → merges in `"espnPlayer"` stub and `"espnSearchMatch"` audit record,
      preserving existing keys like `"minorLeaguePlayerFromSheet"`

  CSV reports are written to `priv/scripts/output/` for each classification.

  ## Usage (via IEx helper)

      MinorLeagueReconciliation.run(:prod, dry_run: true)
      MinorLeagueReconciliation.run(:prod)
      MinorLeagueReconciliation.run(:both)
  """

  import Ecto.Query
  require Logger

  alias TradeMachine.Data.Player
  alias TradeMachine.ESPN.Search

  @default_delay_ms 1_500
  @fuzzy_threshold 0.85
  @max_retries 3
  @retry_backoff_base_ms 10_000

  @type classification :: :exact | :exact_team | :fuzzy | :ambiguous | :no_match | :error

  @type result :: %{
          player_id: String.t(),
          player_name: String.t(),
          mlb_team: String.t() | nil,
          owner_id: String.t() | nil,
          classification: classification(),
          matched_espn_id: integer() | nil,
          matched_espn_name: String.t() | nil,
          matched_espn_team: String.t() | nil,
          jaro_score: float() | nil,
          all_espn_results: [Search.search_result()],
          error: term() | nil
        }

  @doc """
  Run the full reconciliation for the given repo.

  ## Options
    - `:dry_run`     — if true, don't write to DB (default: false)
    - `:delay_ms`    — delay between ESPN API calls in ms (default: #{@default_delay_ms})
    - `:output_dir`  — directory for CSV report files (default: "priv/scripts/output")
    - `:skip_phase1` — skip the nullification step (default: false)
  """
  @spec run(Ecto.Repo.t(), keyword()) :: [result()]
  def run(repo, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    delay_ms = Keyword.get(opts, :delay_ms, @default_delay_ms)
    output_dir = Keyword.get(opts, :output_dir, default_output_dir())
    skip_phase1 = Keyword.get(opts, :skip_phase1, false)

    if dry_run, do: IO.puts("=== DRY RUN MODE (no DB changes) ===\n")

    IO.puts("Repo: #{inspect(repo)}\n")

    unless skip_phase1 do
      IO.puts("Phase 1: Nullifying playerDataId for minor league players...")
      nullified = nullify_minor_league_data_ids(repo, dry_run)
      label = if dry_run, do: "Would nullify", else: "Nullified"
      IO.puts("  #{label} #{nullified} players.\n")
    end

    IO.puts("Phase 2: Fetching minor league players...")
    minor_leaguers = get_minor_leaguers(repo)
    IO.puts("  Found #{length(minor_leaguers)} minor league players to reconcile.\n")

    est_minutes = Float.round(length(minor_leaguers) * delay_ms / 60_000, 1)
    IO.puts("  Searching ESPN (delay=#{delay_ms}ms between requests)...")
    IO.puts("  Estimated time: ~#{est_minutes} minutes\n")

    results = reconcile_all(minor_leaguers, repo, delay_ms, dry_run)

    File.mkdir_p!(output_dir)
    write_reports(results, output_dir)
    print_summary(results)

    results
  end

  # ---------------------------------------------------------------------------
  # Phase 1: Nullify playerDataId
  # ---------------------------------------------------------------------------

  defp nullify_minor_league_data_ids(repo, _dry_run = true) do
    from(p in Player, where: p.league == :minor and not is_nil(p.player_data_id))
    |> repo.aggregate(:count)
  end

  defp nullify_minor_league_data_ids(repo, _dry_run = false) do
    {count, _} =
      from(p in Player, where: p.league == :minor and not is_nil(p.player_data_id))
      |> repo.update_all(set: [player_data_id: nil])

    count
  end

  # ---------------------------------------------------------------------------
  # Phase 2: Search & reconcile
  # ---------------------------------------------------------------------------

  defp get_minor_leaguers(repo) do
    Player
    |> where([p], p.league == :minor)
    |> select([p], %{
      id: p.id,
      name: p.name,
      mlb_team: p.mlb_team,
      meta: p.meta,
      leagueTeamId: p.leagueTeamId
    })
    |> repo.all()
  end

  defp reconcile_all(players, repo, delay_ms, dry_run) do
    total = length(players)

    players
    |> Enum.with_index(1)
    |> Enum.map(fn {player, idx} ->
      if rem(idx, 50) == 0 or idx == 1 or idx == total do
        IO.puts("  [#{idx}/#{total}] #{player.name}...")
      end

      result = search_with_retry(player)

      if not dry_run and result.classification in [:exact, :exact_team] do
        apply_match(player, result, repo)
      end

      if idx < total, do: Process.sleep(delay_ms)

      result
    end)
  end

  defp search_with_retry(player, attempt \\ 0) do
    case Search.search_mlb_player(player.name) do
      {:ok, espn_results} ->
        classify(player, espn_results)

      {:error, :rate_limited} when attempt < @max_retries ->
        backoff = @retry_backoff_base_ms * trunc(:math.pow(2, attempt))

        IO.puts(
          "    Rate limited, backing off #{backoff}ms " <>
            "(attempt #{attempt + 1}/#{@max_retries})..."
        )

        Process.sleep(backoff)
        search_with_retry(player, attempt + 1)

      {:error, reason} ->
        build_result(player, :error, [], nil, nil, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  defp classify(player, []) do
    build_result(player, :no_match, [], nil, nil)
  end

  defp classify(player, espn_results) do
    exact_matches =
      Enum.filter(espn_results, fn r ->
        names_match_exact?(player.name, r.name)
      end)

    case exact_matches do
      [single] ->
        build_result(player, :exact, espn_results, single, 1.0)

      [_ | _] = multiple ->
        try_disambiguate_by_team(player, multiple, espn_results)

      [] ->
        try_fuzzy_match(player, espn_results)
    end
  end

  defp try_disambiguate_by_team(player, exact_matches, all_results) do
    team_matched =
      if player.mlb_team do
        Enum.filter(exact_matches, fn r ->
          team_matches?(player.mlb_team, r.team)
        end)
      else
        []
      end

    case team_matched do
      [single] ->
        build_result(player, :exact_team, all_results, single, 1.0)

      _ ->
        build_result(player, :ambiguous, all_results, List.first(exact_matches), nil)
    end
  end

  defp try_fuzzy_match(player, espn_results) do
    best =
      espn_results
      |> Enum.map(fn r ->
        score =
          String.jaro_distance(
            String.downcase(player.name),
            String.downcase(r.name)
          )

        {r, score}
      end)
      |> Enum.filter(fn {_, score} -> score >= @fuzzy_threshold end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)
      |> List.first()

    case best do
      {match, score} ->
        build_result(player, :fuzzy, espn_results, match, score)

      nil ->
        build_result(player, :no_match, espn_results, nil, nil)
    end
  end

  # ---------------------------------------------------------------------------
  # Apply match to DB
  # ---------------------------------------------------------------------------

  defp apply_match(player, result, repo) do
    espn_id = result.matched_espn_id
    espn_name = result.matched_espn_name
    espn_team = result.matched_espn_team

    existing_meta =
      Player
      |> where([p], p.id == ^player.id)
      |> select([p], p.meta)
      |> repo.one()

    new_meta =
      Map.merge(existing_meta || %{}, %{
        "espnPlayer" => %{
          "id" => espn_id,
          "player" => %{"fullName" => espn_name},
          "source" => "espn_search_reconciliation"
        },
        "espnSearchMatch" => %{
          "espnId" => espn_id,
          "espnName" => espn_name,
          "espnTeam" => espn_team,
          "matchedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "classification" => to_string(result.classification)
        }
      })

    from(p in Player, where: p.id == ^player.id)
    |> repo.update_all(set: [player_data_id: espn_id, meta: new_meta])
  end

  # ---------------------------------------------------------------------------
  # Result building
  # ---------------------------------------------------------------------------

  defp build_result(player, classification, espn_results, matched, score, error \\ nil) do
    %{
      player_id: player.id,
      player_name: player.name,
      mlb_team: player.mlb_team,
      owner_id: player.leagueTeamId,
      classification: classification,
      matched_espn_id: matched && matched.espn_id,
      matched_espn_name: matched && matched.name,
      matched_espn_team: matched && matched.team,
      jaro_score: score,
      all_espn_results: espn_results,
      error: error
    }
  end

  # ---------------------------------------------------------------------------
  # Name / team matching helpers
  # ---------------------------------------------------------------------------

  defp names_match_exact?(db_name, espn_name)
       when is_binary(db_name) and is_binary(espn_name) do
    normalize_name(db_name) == normalize_name(espn_name)
  end

  defp names_match_exact?(_, _), do: false

  defp normalize_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[.\-']/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @team_name_map %{
    "ARI" => "diamondbacks",
    "ATL" => "braves",
    "BAL" => "orioles",
    "BOS" => "red sox",
    "CHC" => "cubs",
    "CHW" => "white sox",
    "CIN" => "reds",
    "CLE" => "guardians",
    "COL" => "rockies",
    "DET" => "tigers",
    "HOU" => "astros",
    "KC" => "royals",
    "LAA" => "angels",
    "LAD" => "dodgers",
    "MIA" => "marlins",
    "MIL" => "brewers",
    "MIN" => "twins",
    "NYM" => "mets",
    "NYY" => "yankees",
    "OAK" => "athletics",
    "PHI" => "phillies",
    "PIT" => "pirates",
    "SD" => "padres",
    "SF" => "giants",
    "SEA" => "mariners",
    "STL" => "cardinals",
    "TB" => "rays",
    "TEX" => "rangers",
    "TOR" => "blue jays",
    "WSH" => "nationals"
  }

  defp team_matches?(db_team, espn_team_subtitle)
       when is_binary(db_team) and is_binary(espn_team_subtitle) do
    db_upper = String.upcase(db_team)
    espn_lower = String.downcase(espn_team_subtitle)

    case Map.get(@team_name_map, db_upper) do
      nil -> false
      team_name -> String.contains?(espn_lower, team_name)
    end
  end

  defp team_matches?(_, _), do: false

  # ---------------------------------------------------------------------------
  # Reports
  # ---------------------------------------------------------------------------

  defp print_summary(results) do
    grouped = Enum.group_by(results, & &1.classification)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("RECONCILIATION SUMMARY")
    IO.puts(String.duplicate("=", 60))
    IO.puts("  Total players:    #{length(results)}")
    IO.puts("  Exact matches:    #{length(grouped[:exact] || [])}")
    IO.puts("  Exact (by team):  #{length(grouped[:exact_team] || [])}")
    IO.puts("  Fuzzy matches:    #{length(grouped[:fuzzy] || [])}")
    IO.puts("  Ambiguous:        #{length(grouped[:ambiguous] || [])}")
    IO.puts("  No match:         #{length(grouped[:no_match] || [])}")
    IO.puts("  Errors:           #{length(grouped[:error] || [])}")
    IO.puts(String.duplicate("=", 60))

    applied = length(grouped[:exact] || []) + length(grouped[:exact_team] || [])
    IO.puts("\n  Applied #{applied} matches to DB (exact + exact_team).")
    IO.puts("  Review fuzzy/ambiguous/no-match CSVs in priv/scripts/output/\n")
  end

  defp write_reports(results, output_dir) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")

    for classification <- [:exact, :exact_team, :fuzzy, :ambiguous, :no_match, :error] do
      write_csv(results, classification, "#{output_dir}/#{classification}_#{timestamp}.csv")
    end
  end

  defp write_csv(results, classification, path) do
    filtered = Enum.filter(results, &(&1.classification == classification))

    if filtered == [] do
      IO.puts("  No #{classification} results — skipping #{Path.basename(path)}")
    else
      header =
        "player_id,player_name,mlb_team,owner_id," <>
          "matched_espn_id,matched_espn_name,matched_espn_team," <>
          "jaro_score,all_espn_results\n"

      rows = Enum.map_join(filtered, "\n", &result_to_csv_row/1)

      File.write!(path, header <> rows <> "\n")
      IO.puts("  Wrote #{length(filtered)} #{classification} results to #{path}")
    end
  end

  defp result_to_csv_row(r) do
    espn_summary =
      r.all_espn_results
      |> Enum.map(fn er -> "#{er.espn_id}:#{er.name}" end)
      |> Enum.join("; ")

    [
      r.player_id,
      csv_escape(r.player_name),
      r.mlb_team || "",
      r.owner_id || "",
      if(r.matched_espn_id, do: to_string(r.matched_espn_id), else: ""),
      csv_escape(r.matched_espn_name || ""),
      csv_escape(r.matched_espn_team || ""),
      if(r.jaro_score, do: Float.round(r.jaro_score, 3) |> to_string(), else: ""),
      csv_escape(espn_summary)
    ]
    |> Enum.join(",")
  end

  defp default_output_dir do
    case :code.priv_dir(:trade_machine) do
      {:error, _} -> "/tmp/reconciliation_output"
      priv_dir -> Path.join(to_string(priv_dir), "scripts/output")
    end
  end

  defp csv_escape(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]) do
      "\"" <> String.replace(val, "\"", "\"\"") <> "\""
    else
      val
    end
  end

  defp csv_escape(_), do: ""
end
