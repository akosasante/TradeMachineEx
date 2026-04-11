defmodule TradeMachine.Data.TeamCsvLabel do
  @moduledoc false

  import Ecto.Query

  alias TradeMachine.Data.{Team, User}

  @doc """
  Map of team id (canonical string) -> label for owner-facing copy.

  Uses the first non-blank `csv_name` on any user for that team (ordered by user id),
  otherwise `team.name`. Matches `TradeMachine.Discord.Formatter.format_participant_name/2`
  when a single owner has a csv name.
  """
  @spec labels_by_team_id([term()], Ecto.Repo.t()) :: %{String.t() => String.t()}
  def labels_by_team_id(team_ids, repo) when is_list(team_ids) do
    team_ids =
      team_ids
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map(&id_key/1)
      |> Enum.uniq()

    if team_ids == [] do
      %{}
    else
      team_names =
        from(t in Team,
          where: t.id in ^team_ids,
          select: {t.id, t.name}
        )
        |> repo.all()
        |> Map.new(fn {id, name} -> {id_key(id), name} end)

      csv_first =
        from(u in User,
          where: u.teamId in ^team_ids,
          where: not is_nil(u.csv_name),
          where: u.csv_name != "",
          order_by: [asc: u.id],
          select: {u.teamId, u.csv_name}
        )
        |> repo.all()
        |> Enum.reduce(%{}, fn {team_id, csv}, acc ->
          k = id_key(team_id)
          if Map.has_key?(acc, k), do: acc, else: Map.put(acc, k, csv)
        end)

      Map.new(team_ids, fn team_id ->
        label = Map.get(csv_first, team_id) || Map.get(team_names, team_id) || "Unknown"
        {team_id, label}
      end)
    end
  end

  defp id_key(id) when is_binary(id), do: id
  defp id_key(id), do: to_string(id)
end
