defmodule TradeMachine.DraftPicks.Sync do
  @moduledoc """
  Syncs parsed draft pick data from the Google Sheet to the database.

  For each non-cleared pick returned by `TradeMachine.DraftPicks.Parser`:

  1. Resolves both `original_owner_csv` and `current_owner_csv` to team IDs
     via `User.csv_name`.
  2. Upserts the pick into the `draft_pick` table, keyed on the unique
     constraint `(type, season, round, originalOwnerId)`.
  3. On conflict (the pick already exists), updates `currentOwnerId`,
     `pick_number`, and `last_synced_at` to reflect the latest sheet state.

  The minor league season is resolved at call time from the
  `draft_picks_season_thresholds` config. Major league picks use
  `minor_season + 1` (their draft is always the following year). If today
  precedes all configured thresholds the function raises a `RuntimeError` so
  stale config is immediately visible rather than silently producing wrong data.

  There is **no stale-clearing step**: cleared picks on the sheet (OVR ≤ 0)
  are simply absent from the parsed list and stay in the DB with their last
  known owner. The TypeScript server owns `currentOwnerId` changes from trades.
  """

  import Ecto.Query
  require Logger

  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.User

  @type parsed_pick :: TradeMachine.DraftPicks.Parser.parsed_pick()

  @type sync_stats :: %{
          upserted: non_neg_integer(),
          skipped_no_owner: non_neg_integer()
        }

  @doc """
  Syncs a list of parsed picks from the sheet into the given repo.

  Returns `{:ok, stats}` with counts of upserted and skipped picks, or
  `{:error, term}` if an unexpected error occurs.

  Raises `RuntimeError` if today precedes all season thresholds in config.
  """
  @spec sync_from_sheet([parsed_pick()], Ecto.Repo.t()) ::
          {:ok, sync_stats()} | {:error, term()}
  def sync_from_sheet(parsed_picks, repo) when is_list(parsed_picks) do
    minor_season = resolve_season()
    owner_map = build_owner_map(repo)
    now = DateTime.utc_now()

    {upserted, skipped} =
      Enum.reduce(parsed_picks, {0, 0}, fn pick, {upserted, skipped} ->
        case resolve_owners(pick, owner_map) do
          {:ok, orig_team_id, curr_team_id} ->
            season = season_for_pick(pick.type, minor_season)
            upsert_pick(pick, season, orig_team_id, curr_team_id, now, repo)
            {upserted + 1, skipped}

          {:error, reason} ->
            Logger.warning("Skipping draft pick: #{reason}",
              original_owner: pick.original_owner_csv,
              current_owner: pick.current_owner_csv,
              round: inspect(pick.round),
              type: pick.type
            )

            {upserted, skipped + 1}
        end
      end)

    stats = %{upserted: upserted, skipped_no_owner: skipped}

    Logger.info("Draft picks sync completed",
      repo: inspect(repo),
      minor_season: minor_season,
      major_season: minor_season + 1,
      upserted: upserted,
      skipped_no_owner: skipped
    )

    {:ok, stats}
  rescue
    e ->
      Logger.error("Draft picks sync failed", error: Exception.message(e))
      {:error, e}
  end

  # ---------------------------------------------------------------------------
  # Season resolution
  # ---------------------------------------------------------------------------

  @doc """
  Resolves the **minor league season** from `draft_picks_season_thresholds` config.

  Iterates the thresholds in **config list order** and returns the season for the
  first threshold whose date is on or before the reference UTC date (defaults to
  today). Keep thresholds sorted **descending by date** in `config.exs` so the
  first match is the correct season for that calendar window.

  Minor league picks (`:high`, `:low`) use this value directly. Major league
  picks use `minor_season + 1` via `season_for_pick/2` — the MLB draft is
  always held the following year.

  Pass an explicit `Date` in tests to avoid calendar-dependent assertions.

  Raises `RuntimeError` if the reference date precedes all configured thresholds — this
  forces a code update rather than silently using stale season data.
  """
  @spec resolve_season() :: integer()
  @spec resolve_season(Date.t()) :: integer()
  def resolve_season(today \\ Date.utc_today()) when is_struct(today, Date) do
    thresholds = Application.fetch_env!(:trade_machine, :draft_picks_season_thresholds)

    case Enum.find(thresholds, fn {threshold_date, _season} ->
           Date.compare(today, threshold_date) != :lt
         end) do
      {_date, season} ->
        season

      nil ->
        raise RuntimeError,
          message:
            "No matching draft season for date (#{inspect(today)}). " <>
              "Update :draft_picks_season_thresholds in config/config.exs."
    end
  end

  # Major league picks belong to the draft happening in the spring of the
  # following year; minor league picks belong to the draft in the fall of the
  # current MLB season.
  defp season_for_pick(:majors, minor_season), do: minor_season + 1
  defp season_for_pick(_type, minor_season), do: minor_season

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

  defp resolve_owners(pick, owner_map) do
    orig_team_id = Map.get(owner_map, pick.original_owner_csv)
    curr_team_id = Map.get(owner_map, pick.current_owner_csv)

    cond do
      is_nil(orig_team_id) ->
        {:error, "original_owner_csv '#{pick.original_owner_csv}' not found in owner map"}

      is_nil(curr_team_id) ->
        {:error, "current_owner_csv '#{pick.current_owner_csv}' not found in owner map"}

      true ->
        {:ok, orig_team_id, curr_team_id}
    end
  end

  # ---------------------------------------------------------------------------
  # Upsert
  # ---------------------------------------------------------------------------

  # We use an explicit get-then-insert-or-update pattern rather than
  # ON CONFLICT because the unique constraint involves a camelCase column
  # ("originalOwnerId") that Ecto's conflict_target helpers do not handle
  # reliably with the field_source_mapper in use.
  defp upsert_pick(pick, season, orig_team_id, curr_team_id, now, repo) do
    existing =
      DraftPick
      |> where(
        [p],
        p.type == ^pick.type and
          p.season == ^season and
          p.originalOwnerId == ^orig_team_id
      )
      |> where([p], fragment("round = ?::numeric", ^pick.round))
      |> repo.one()

    case existing do
      nil ->
        insert_pick(pick, season, orig_team_id, curr_team_id, now, repo)

      record ->
        update_pick(record, curr_team_id, pick.pick_number, now, repo)
    end
  end

  defp insert_pick(pick, season, orig_team_id, curr_team_id, now, repo) do
    changeset =
      %DraftPick{}
      |> Ecto.Changeset.cast(
        %{
          type: pick.type,
          round: pick.round,
          season: season,
          pick_number: pick.pick_number,
          currentOwnerId: curr_team_id,
          originalOwnerId: orig_team_id,
          last_synced_at: now
        },
        [:type, :round, :season, :pick_number, :currentOwnerId, :originalOwnerId, :last_synced_at]
      )
      |> Ecto.Changeset.validate_required([:type, :round, :season])

    case repo.insert(changeset) do
      {:ok, _pick} ->
        :ok

      {:error, cs} ->
        Logger.warning("Failed to insert draft pick",
          errors: inspect(cs.errors),
          original_owner: orig_team_id,
          round: inspect(pick.round),
          type: pick.type
        )
    end
  end

  defp update_pick(record, curr_team_id, pick_number, now, repo) do
    record
    |> Ecto.Changeset.change(%{
      currentOwnerId: curr_team_id,
      pick_number: pick_number,
      last_synced_at: now
    })
    |> repo.update()
    |> case do
      {:ok, _pick} ->
        :ok

      {:error, cs} ->
        Logger.warning("Failed to update draft pick",
          errors: inspect(cs.errors),
          pick_id: record.id
        )
    end
  end
end
