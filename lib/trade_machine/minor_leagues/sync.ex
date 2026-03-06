defmodule TradeMachine.MinorLeagues.Sync do
  @moduledoc """
  Syncs parsed minor league player data from the Google Sheet to the database.

  Implements a matching engine that:
  1. Resolves sheet owner names to team IDs via `User.csv_name`
  2. Matches incoming players to DB players, primarily via `meta.minorLeaguePlayerFromSheet`,
     falling back to top-level `name` + `league` + `mlb_team`
  3. Updates matched players (meta, top-level fields, owner)
  4. Inserts unmatched players as new minor leaguers
  5. Clears `leagueTeamId` for owned minor leaguers no longer on the sheet
  """

  import Ecto.Query
  require Logger

  alias TradeMachine.Data.Player
  alias TradeMachine.Data.User

  @type parsed_player :: TradeMachine.MinorLeagues.Parser.parsed_player()

  @type sync_stats :: %{
          matched: non_neg_integer(),
          inserted: non_neg_integer(),
          cleared: non_neg_integer(),
          skipped_no_owner: non_neg_integer()
        }

  @doc """
  Syncs a list of parsed players from the sheet into the given repo.

  Returns `{:ok, stats}` with counts of matched, inserted, cleared, and skipped players.
  """
  @spec sync_from_sheet([parsed_player()], Ecto.Repo.t()) ::
          {:ok, sync_stats()} | {:error, term()}
  def sync_from_sheet(parsed_players, repo) when is_list(parsed_players) do
    owner_map = build_owner_map(repo)
    db_minors = get_all_minor_leaguers(repo)

    {meta_index, fallback_index} = build_indexes(db_minors)

    {matched_ids, match_count, insert_count, skip_count} =
      process_players(parsed_players, owner_map, meta_index, fallback_index, repo)

    cleared_count = clear_stale_owners(db_minors, matched_ids, repo)

    stats = %{
      matched: match_count,
      inserted: insert_count,
      cleared: cleared_count,
      skipped_no_owner: skip_count
    }

    Logger.info("Minor league sync completed",
      repo: inspect(repo),
      matched: match_count,
      inserted: insert_count,
      cleared: cleared_count,
      skipped_no_owner: skip_count
    )

    {:ok, stats}
  rescue
    e ->
      Logger.error("Minor league sync failed", error: Exception.message(e))
      {:error, e}
  end

  # ---------------------------------------------------------------------------
  # Owner resolution
  # ---------------------------------------------------------------------------

  @doc false
  def build_owner_map(repo) do
    User
    |> where([u], not is_nil(u.csv_name) and not is_nil(u.teamId))
    |> select([u], {u.csv_name, u.teamId})
    |> repo.all()
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Load existing minor leaguers
  # ---------------------------------------------------------------------------

  defp get_all_minor_leaguers(repo) do
    Player
    |> where([p], p.league == :minor)
    |> select([p], %{p | meta: p.meta})
    |> repo.all()
  end

  # ---------------------------------------------------------------------------
  # Indexing for matching
  # ---------------------------------------------------------------------------

  defp build_indexes(db_minors) do
    meta_index =
      db_minors
      |> Enum.filter(fn p -> p.meta && p.meta["minorLeaguePlayerFromSheet"] end)
      |> Enum.reduce(%{}, fn p, acc ->
        sheet_data = p.meta["minorLeaguePlayerFromSheet"]
        key = meta_key(sheet_data["name"] || p.name, sheet_data)
        Map.put(acc, key, p)
      end)

    fallback_index =
      db_minors
      |> Enum.reduce(%{}, fn p, acc ->
        key = fallback_key(p.name, p.mlb_team)
        Map.put(acc, key, p)
      end)

    {meta_index, fallback_index}
  end

  defp meta_key(name, sheet_data) do
    {
      String.downcase(name || ""),
      String.downcase(sheet_data["leagueLevel"] || ""),
      String.downcase(sheet_data["mlbTeam"] || ""),
      String.downcase(sheet_data["position"] || "")
    }
  end

  defp fallback_key(name, mlb_team) do
    {String.downcase(name || ""), String.downcase(mlb_team || "")}
  end

  # ---------------------------------------------------------------------------
  # Process each parsed player
  # ---------------------------------------------------------------------------

  defp process_players(parsed_players, owner_map, meta_index, fallback_index, repo) do
    now = DateTime.utc_now()

    Enum.reduce(parsed_players, {MapSet.new(), 0, 0, 0}, fn parsed,
                                                            {matched_ids, matched, inserted,
                                                             skipped} ->
      case resolve_owner(parsed.owner_csv_name, owner_map) do
        nil ->
          Logger.warning("Could not resolve owner for player",
            player: parsed.name,
            owner_csv_name: parsed.owner_csv_name
          )

          {matched_ids, matched, inserted, skipped + 1}

        team_id ->
          upsert_player(parsed, team_id, meta_index, fallback_index, now, repo,
            matched_ids: matched_ids,
            matched: matched,
            inserted: inserted,
            skipped: skipped
          )
      end
    end)
  end

  defp upsert_player(parsed, team_id, meta_index, fallback_index, now, repo, counters) do
    matched_ids = Keyword.fetch!(counters, :matched_ids)
    matched = Keyword.fetch!(counters, :matched)
    inserted = Keyword.fetch!(counters, :inserted)
    skipped = Keyword.fetch!(counters, :skipped)

    sheet_meta = %{
      "name" => parsed.name,
      "position" => parsed.position,
      "leagueLevel" => parsed.league_level,
      "mlbTeam" => parsed.mlb_team
    }

    case find_match(parsed, meta_index, fallback_index) do
      {:ok, db_player} ->
        update_player(db_player, parsed, sheet_meta, team_id, now, repo)
        {MapSet.put(matched_ids, db_player.id), matched + 1, inserted, skipped}

      :no_match ->
        insert_player(parsed, sheet_meta, team_id, now, repo)
        {matched_ids, matched, inserted + 1, skipped}
    end
  end

  defp resolve_owner(owner_csv_name, owner_map) do
    Map.get(owner_map, owner_csv_name)
  end

  defp find_match(parsed, meta_index, fallback_index) do
    incoming_meta_key =
      meta_key(parsed.name, %{
        "leagueLevel" => parsed.league_level,
        "mlbTeam" => parsed.mlb_team,
        "position" => parsed.position
      })

    case Map.get(meta_index, incoming_meta_key) do
      %Player{} = p ->
        {:ok, p}

      nil ->
        incoming_fallback_key = fallback_key(parsed.name, parsed.mlb_team)

        case Map.get(fallback_index, incoming_fallback_key) do
          %Player{} = p -> {:ok, p}
          nil -> :no_match
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Update / Insert
  # ---------------------------------------------------------------------------

  defp update_player(db_player, parsed, sheet_meta, team_id, now, repo) do
    existing_meta = db_player.meta || %{}

    new_meta =
      existing_meta
      |> Map.put("minorLeaguePlayerFromSheet", sheet_meta)
      |> Map.put("position", parsed.position)

    changeset =
      db_player
      |> Ecto.Changeset.change(%{
        name: parsed.name,
        mlb_team: parsed.mlb_team,
        meta: new_meta,
        leagueTeamId: team_id,
        last_synced_at: now
      })

    case repo.update(changeset) do
      {:ok, _player} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to update minor leaguer",
          player_id: db_player.id,
          name: parsed.name,
          errors: inspect(changeset.errors)
        )
    end
  end

  defp insert_player(parsed, sheet_meta, team_id, now, repo) do
    params = %{
      name: parsed.name,
      league: :minor,
      mlb_team: parsed.mlb_team,
      leagueTeamId: team_id,
      meta: %{"minorLeaguePlayerFromSheet" => sheet_meta, "position" => parsed.position},
      last_synced_at: now
    }

    case Player.new(params) |> repo.insert() do
      {:ok, _player} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to insert minor leaguer",
          name: parsed.name,
          errors: inspect(changeset.errors)
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Clear stale owners
  # ---------------------------------------------------------------------------

  defp clear_stale_owners(db_minors, matched_ids, repo) do
    stale_ids =
      db_minors
      |> Enum.filter(fn p ->
        not is_nil(p.leagueTeamId) and
          not MapSet.member?(matched_ids, p.id)
      end)
      |> Enum.map(& &1.id)

    if stale_ids == [] do
      0
    else
      {count, _} =
        Player
        |> where([p], p.id in ^stale_ids)
        |> repo.update_all(set: [leagueTeamId: nil])

      Logger.info("Cleared ownership for stale minor leaguers", count: count)
      count
    end
  end
end
