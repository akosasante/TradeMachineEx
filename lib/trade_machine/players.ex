defmodule TradeMachine.Players do
  @moduledoc """
  Context module for player-related operations.

  Provides functions for syncing ESPN major league player data, including
  a multi-phase matching engine that handles duplicate names and ownership-based
  disambiguation.
  """

  import Ecto.Query
  require Logger

  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Team
  alias TradeMachine.ESPN.Constants

  @default_skip_window_seconds 300

  @doc """
  Syncs ESPN player data to the database for a single repo.

  Runs the three-phase matching engine:
  1. Match by `playerDataId`
  2. Claim unclaimed DB players via ownership + name/team/position
  3. Insert new players not yet in DB

  ## Options
    - `:skip_if_synced_within` - seconds; skip updating players whose
      `last_synced_at` is more recent than this (default: 300)
  """
  @spec sync_espn_player_data([map()], Ecto.Repo.t(), keyword()) ::
          {:ok,
           %{updated: non_neg_integer(), inserted: non_neg_integer(), skipped: non_neg_integer()}}
          | {:error, term()}
  def sync_espn_player_data(espn_players, repo, opts \\ []) when is_list(espn_players) do
    skip_window = Keyword.get(opts, :skip_if_synced_within, @default_skip_window_seconds)
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -skip_window, :second)

    espn_players = dedup_espn_players(espn_players)

    Logger.info("Starting ESPN player sync",
      espn_count: length(espn_players),
      repo: inspect(repo)
    )

    db_players = get_syncable_players(repo)
    teams = get_teams_with_espn_id(repo)

    {updates, inserts, skipped_count} =
      run_matching_engine(espn_players, db_players, teams, now, cutoff)

    update_ids = Enum.map(updates, fn %{db_player: p} -> p.id end)
    meta_by_id = fetch_meta_for_players(update_ids, repo)
    updates = backfill_meta(updates, meta_by_id)

    repo.transaction(fn ->
      updated_count = execute_updates(updates, repo)
      inserted_count = execute_inserts(inserts, repo)

      stats = %{
        updated: updated_count,
        inserted: inserted_count,
        skipped: skipped_count
      }

      Logger.info("ESPN player sync completed",
        updated: updated_count,
        inserted: inserted_count,
        skipped: skipped_count,
        repo: inspect(repo)
      )

      stats
    end)
  end

  @doc """
  Loads all players that should be considered for ESPN sync:
  major leaguers (league=1) OR players with a non-null playerDataId.

  The `meta` JSONB column is intentionally excluded (it has `load_in_query: false`)
  to avoid loading large blobs for every player. Meta is fetched separately for
  only the players that need updating via `fetch_meta_for_players/2`.
  """
  @spec get_syncable_players(Ecto.Repo.t()) :: [Player.t()]
  def get_syncable_players(repo) do
    Player
    |> where([p], p.league == :major or not is_nil(p.player_data_id))
    |> repo.all()
  end

  @spec get_teams_with_espn_id(Ecto.Repo.t()) :: [Team.t()]
  defp get_teams_with_espn_id(repo) do
    Team
    |> where([t], not is_nil(t.espn_id))
    |> repo.all()
  end

  @spec fetch_meta_for_players([Ecto.UUID.t()], Ecto.Repo.t()) :: %{Ecto.UUID.t() => map()}
  defp fetch_meta_for_players([], _repo), do: %{}

  defp fetch_meta_for_players(player_ids, repo) do
    Player
    |> where([p], p.id in ^player_ids)
    |> select([p], {p.id, p.meta})
    |> repo.all()
    |> Map.new()
  end

  defp backfill_meta(updates, meta_by_id) do
    Enum.map(updates, fn %{db_player: db_player, changes: changes} = update ->
      existing_meta = Map.get(meta_by_id, db_player.id) || %{}
      merged_meta = Map.merge(existing_meta, changes.meta)
      %{update | changes: %{changes | meta: merged_meta}}
    end)
  end

  # ---------------------------------------------------------------------------
  # Matching engine
  # ---------------------------------------------------------------------------

  defp run_matching_engine(espn_players, db_players, teams, now, cutoff) do
    espn_by_id = Map.new(espn_players, fn ep -> {ep["id"], ep} end)
    teams_by_db_id = Map.new(teams, fn t -> {t.id, t} end)
    teams_by_espn_id = Map.new(teams, fn t -> {t.espn_id, t} end)

    {phase1_updates, matched_espn_ids, matched_db_ids} =
      phase1_match_by_data_id(db_players, espn_by_id, now, cutoff)

    unclaimed_db =
      Enum.filter(db_players, fn p ->
        p.player_data_id == nil and
          p.league == :major and
          p.id not in matched_db_ids
      end)

    remaining_espn =
      Enum.reject(espn_players, fn ep -> MapSet.member?(matched_espn_ids, ep["id"]) end)

    {phase2_updates, phase2_matched_espn_ids, phase2_matched_db_ids} =
      phase2_claim_unclaimed(
        unclaimed_db,
        remaining_espn,
        teams_by_db_id,
        teams_by_espn_id,
        now,
        cutoff
      )

    all_matched_espn_ids = MapSet.union(matched_espn_ids, phase2_matched_espn_ids)
    all_matched_db_ids = MapSet.union(matched_db_ids, phase2_matched_db_ids)

    inserts =
      phase3_collect_inserts(espn_players, all_matched_espn_ids, now)

    skipped_count = count_retired_or_missing(db_players, espn_by_id, all_matched_db_ids)

    all_updates = phase1_updates ++ phase2_updates
    {skip_updates, real_updates} = split_by_cutoff(all_updates, cutoff)

    {real_updates, inserts, length(skip_updates) + skipped_count}
  end

  # Phase 1: match DB players that already have a playerDataId to ESPN by id
  defp phase1_match_by_data_id(db_players, espn_by_id, now, _cutoff) do
    db_with_data_id = Enum.filter(db_players, &(&1.player_data_id != nil))

    Enum.reduce(db_with_data_id, {[], MapSet.new(), MapSet.new()}, fn db_player,
                                                                      {updates, espn_ids, db_ids} ->
      case Map.get(espn_by_id, db_player.player_data_id) do
        nil ->
          {updates, espn_ids, db_ids}

        espn_player ->
          update = build_update(db_player, espn_player, now)

          {[update | updates], MapSet.put(espn_ids, espn_player["id"]),
           MapSet.put(db_ids, db_player.id)}
      end
    end)
  end

  # Phase 2: claim unclaimed DB major leaguers by ownership or name/team/position
  defp phase2_claim_unclaimed(
         unclaimed_db,
         remaining_espn,
         teams_by_db_id,
         _teams_by_espn_id,
         now,
         _cutoff
       ) do
    espn_by_name = group_by_name(remaining_espn)

    Enum.reduce(unclaimed_db, {[], MapSet.new(), MapSet.new()}, fn db_player,
                                                                   {updates, espn_ids, db_ids} ->
      result =
        try_ownership_match(db_player, remaining_espn, espn_ids, teams_by_db_id)
        |> case do
          {:ok, espn_player} ->
            {:ok, espn_player}

          :no_match ->
            try_name_team_position_match(db_player, espn_by_name, espn_ids)
        end

      case result do
        {:ok, espn_player} ->
          update = build_update(db_player, espn_player, now, _claim: true)

          {[update | updates], MapSet.put(espn_ids, espn_player["id"]),
           MapSet.put(db_ids, db_player.id)}

        :no_match ->
          {updates, espn_ids, db_ids}
      end
    end)
  end

  # 2a: ownership-based match -- DB player is owned, find ESPN player on same fantasy team
  defp try_ownership_match(db_player, remaining_espn, already_matched_espn_ids, teams_by_db_id) do
    with league_team_id when not is_nil(league_team_id) <- db_player.leagueTeamId,
         %Team{espn_id: espn_team_id} when not is_nil(espn_team_id) <-
           Map.get(teams_by_db_id, league_team_id) do
      candidates =
        Enum.filter(remaining_espn, fn ep ->
          not MapSet.member?(already_matched_espn_ids, ep["id"]) and
            ep["status"] == "ONTEAM" and
            ep["onTeamId"] == espn_team_id and
            get_in(ep, ["player", "fullName"]) == db_player.name
        end)

      pick_single_candidate(candidates, db_player)
    else
      _ -> :no_match
    end
  end

  # 2b/2c: match by name, then disambiguate by mlbTeam, then by position
  defp try_name_team_position_match(db_player, espn_by_name, already_matched_espn_ids) do
    candidates =
      Map.get(espn_by_name, db_player.name, [])
      |> Enum.reject(fn ep -> MapSet.member?(already_matched_espn_ids, ep["id"]) end)

    case candidates do
      [] ->
        :no_match

      [single] ->
        {:ok, single}

      multiple ->
        disambiguate_by_team_then_position(multiple, db_player)
    end
  end

  defp disambiguate_by_team_then_position(candidates, db_player) do
    by_team =
      if db_player.mlb_team do
        Enum.filter(candidates, fn ep ->
          Constants.mlb_team_abbrev(get_in(ep, ["player", "proTeamId"])) == db_player.mlb_team
        end)
      else
        candidates
      end

    case by_team do
      [single] ->
        {:ok, single}

      [] ->
        pick_single_candidate(candidates, db_player)

      still_multiple ->
        disambiguate_by_position(still_multiple, db_player)
    end
  end

  defp disambiguate_by_position(candidates, db_player) do
    db_position = get_in(db_player.meta || %{}, ["espnPlayer", "player", "defaultPositionId"])

    if db_position do
      by_pos =
        Enum.filter(candidates, fn ep ->
          get_in(ep, ["player", "defaultPositionId"]) == db_position
        end)

      pick_single_candidate(if(by_pos == [], do: candidates, else: by_pos), db_player)
    else
      pick_single_candidate(candidates, db_player)
    end
  end

  defp pick_single_candidate([single], _db_player), do: {:ok, single}

  defp pick_single_candidate(candidates, db_player) when length(candidates) > 1 do
    Logger.warning(
      "Ambiguous ESPN match for player #{db_player.name} (id=#{db_player.id}): " <>
        "#{length(candidates)} candidates, skipping",
      player_id: db_player.id,
      candidate_ids: Enum.map(candidates, & &1["id"])
    )

    :no_match
  end

  defp pick_single_candidate(_, _db_player), do: :no_match

  # Phase 3: ESPN players not matched to any DB player become inserts
  defp phase3_collect_inserts(espn_players, all_matched_espn_ids, now) do
    espn_players
    |> Enum.reject(fn ep -> MapSet.member?(all_matched_espn_ids, ep["id"]) end)
    |> Enum.map(fn ep -> build_insert(ep, now) end)
  end

  defp count_retired_or_missing(db_players, espn_by_id, matched_db_ids) do
    db_players
    |> Enum.filter(fn p ->
      p.player_data_id != nil and
        not MapSet.member?(matched_db_ids, p.id) and
        not Map.has_key?(espn_by_id, p.player_data_id)
    end)
    |> length()
  end

  # ---------------------------------------------------------------------------
  # Build update / insert payloads
  # ---------------------------------------------------------------------------

  defp build_update(db_player, espn_player, now, opts \\ []) do
    claim? = Keyword.get(opts, :_claim, false)
    full_name = get_in(espn_player, ["player", "fullName"]) || db_player.name
    pro_team_id = get_in(espn_player, ["player", "proTeamId"])
    position_id = get_in(espn_player, ["player", "defaultPositionId"])
    position_str = Constants.position(position_id)
    mlb_team = Constants.mlb_team_abbrev(pro_team_id) || db_player.mlb_team

    new_meta = %{
      "espnPlayer" => espn_player,
      "position" => position_str
    }

    changes =
      %{
        name: full_name,
        mlb_team: mlb_team,
        meta: new_meta,
        last_synced_at: now
      }

    changes =
      if claim? do
        Map.put(changes, :player_data_id, espn_player["id"])
      else
        changes
      end

    %{db_player: db_player, changes: changes}
  end

  defp build_insert(espn_player, now) do
    full_name = get_in(espn_player, ["player", "fullName"]) || "ESPN Player ##{espn_player["id"]}"
    pro_team_id = get_in(espn_player, ["player", "proTeamId"])
    position_id = get_in(espn_player, ["player", "defaultPositionId"])
    position_str = Constants.position(position_id)
    mlb_team = Constants.mlb_team_abbrev(pro_team_id)

    %{
      id: Ecto.UUID.generate(),
      name: full_name,
      league: :major,
      mlb_team: mlb_team,
      player_data_id: espn_player["id"],
      meta: %{"espnPlayer" => espn_player, "position" => position_str},
      last_synced_at: now
    }
  end

  # ---------------------------------------------------------------------------
  # Idempotency filter
  # ---------------------------------------------------------------------------

  defp split_by_cutoff(updates, cutoff) do
    Enum.split_with(updates, fn %{db_player: db_player} ->
      db_player.last_synced_at != nil and
        DateTime.compare(db_player.last_synced_at, cutoff) == :gt
    end)
  end

  # ---------------------------------------------------------------------------
  # Persistence
  # ---------------------------------------------------------------------------

  defp execute_updates(updates, repo) do
    Enum.each(updates, fn %{db_player: db_player, changes: changes} ->
      db_player
      |> Ecto.Changeset.change(changes)
      |> repo.update!()
    end)

    length(updates)
  end

  defp execute_inserts([], _repo), do: 0

  defp execute_inserts(inserts, repo) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      inserts
      |> Enum.uniq_by(fn ins -> {ins.name, ins.player_data_id} end)
      |> Enum.map(fn insert ->
        insert
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    rows
    |> Enum.chunk_every(50)
    |> Enum.each(fn chunk ->
      repo.insert_all(Player, chunk,
        on_conflict: {:replace, [:meta, :mlb_team, :last_synced_at, :updated_at]},
        conflict_target: [:name, :player_data_id]
      )
    end)

    length(rows)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp dedup_espn_players(espn_players) do
    {deduped, _seen} =
      Enum.reduce(espn_players, {[], MapSet.new()}, fn ep, {acc, seen} ->
        id = ep["id"]

        if MapSet.member?(seen, id) do
          {acc, seen}
        else
          {[ep | acc], MapSet.put(seen, id)}
        end
      end)

    Enum.reverse(deduped)
  end

  defp group_by_name(espn_players) do
    Enum.group_by(espn_players, fn ep ->
      get_in(ep, ["player", "fullName"])
    end)
  end
end
