defmodule TradeMachine.Teams do
  @moduledoc """
  Context module for team-related operations.

  Provides functions for syncing ESPN team data and managing team records.
  """

  require Logger

  alias TradeMachine.Data.Team

  @doc """
  Syncs ESPN team data to the database.

  Takes a list of `TradeMachine.ESPN.Types.FantasyTeam` structs and updates
  the corresponding team records in the database by matching on `espn_id`.

  The function converts each struct to a map and stores it in the `espn_team`
  JSON column. Updates are performed within a transaction for atomicity.

  ## Parameters

    - `espn_teams` - List of `FantasyTeam` structs from ESPN API
    - `repo` - Ecto repo to use (defaults to Production)

  ## Returns

    - `{:ok, %{updated: count, skipped: count}}` - Success with statistics
    - `{:error, reason}` - If transaction fails

  ## Examples

      iex> {:ok, teams} = ESPN.Client.get_league_teams(client)
      iex> Teams.sync_espn_team_data(teams, TradeMachine.Repo.Production)
      {:ok, %{updated: 12, skipped: 0}}
  """
  @spec sync_espn_team_data(
          list(TradeMachine.ESPN.Types.FantasyTeam.t()),
          Ecto.Repo.t()
        ) ::
          {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer()}}
          | {:error, term()}
  def sync_espn_team_data(espn_teams, repo \\ TradeMachine.Repo.Production)
      when is_list(espn_teams) do
    Logger.info("Starting ESPN team data sync",
      team_count: length(espn_teams),
      repo: inspect(repo)
    )

    result =
      repo.transaction(fn ->
        Enum.reduce(espn_teams, %{updated: 0, skipped: 0}, fn espn_team, acc ->
          sync_single_team(espn_team, acc, repo)
        end)
      end)

    case result do
      {:ok, stats} ->
        Logger.info("ESPN team sync completed successfully",
          updated: stats.updated,
          skipped: stats.skipped,
          repo: inspect(repo)
        )

        {:ok, stats}

      {:error, reason} = error ->
        Logger.error("ESPN team sync failed",
          error: inspect(reason),
          repo: inspect(repo)
        )

        error
    end
  end

  # Private function to sync a single team
  defp sync_single_team(espn_team, acc, repo) do
    espn_team_map = struct_to_map(espn_team)
    now = DateTime.utc_now()

    case repo.get_by(Team, espn_id: espn_team.id) do
      nil ->
        Logger.warning("No team found for ESPN ID: #{espn_team.id}",
          espn_id: espn_team.id,
          espn_team_name: espn_team.name
        )

        %{acc | skipped: acc.skipped + 1}

      team ->
        team
        |> Ecto.Changeset.change(
          name: espn_team.name,
          espn_team: espn_team_map,
          last_synced_at: now
        )
        |> repo.update!()

        Logger.debug("Updated team data",
          team_id: team.id,
          espn_id: espn_team.id,
          team_name: espn_team.name
        )

        %{acc | updated: acc.updated + 1}
    end
  end

  # Recursively convert structs to maps, handling nested structs
  defp struct_to_map(struct = %_{}) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {key, struct_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp struct_to_map(list) when is_list(list) do
    Enum.map(list, &struct_to_map/1)
  end

  defp struct_to_map(value), do: value
end
