defmodule TradeMachine.Data.Types.TradedMinor do
  use Ecto.Type

  def type, do: :map

  # Provide custom casting rules.
  # Cast map into string-keyed map to be inserted into db
  def cast(traded_minors) when is_list(traded_minors) or is_map(traded_minors) do
    {:ok, parse(traded_minors)}
  end

  # Everything else is a failure though
  def cast(_), do: :error

  # When loading data from the database, convert string-keyed map into atom-keyed
  def load(traded_minors) when is_list(traded_minors) or is_map(traded_minors) do
    {:ok, load_minors(traded_minors)}
  end

  # When dumping data to the database, we *expect* a string-keyed map
  # but any value could be inserted into the schema struct at runtime,
  # so we need to guard against them.
  def dump(traded_minors) when is_list(traded_minors) do
    if Enum.all?(traded_minors, fn {k, _} -> is_binary(k) end) do
      {:ok, traded_minors}
    else
      :error
    end
  end

  def dump(_), do: :error

  defp parse(traded_minors) when is_list(traded_minors) do
    Enum.map(traded_minors, &parse/1)
  end

  defp parse(traded_minor) when is_map(traded_minor) do
    %{
      "id" => Map.get(traded_minor, :id),
      "league" => Map.get(traded_minor, :league),
      "minorLeagueLevel" => Map.get(traded_minor, :minor_league_level),
      "minorTeam" => Map.get(traded_minor, :minor_team),
      "name" => Map.get(traded_minor, :name),
      "ownerTeam" => Map.get(traded_minor, :owned_by),
      "position" => Map.get(traded_minor, :position),
      "recipient" => Map.get(traded_minor, :recipient),
      "sender" => Map.get(traded_minor, :sender),
      "tradeId" => Map.get(traded_minor, :trade_id)
    }
  end

  defp load_minors(traded_minors) when is_list(traded_minors) do
    Enum.map(traded_minors, &load_minors/1)
  end

  defp load_minors(traded_minor) when is_map(traded_minor) do
    %{
      id: Map.get(traded_minor, "id"),
      league: Map.get(traded_minor, "league"),
      minor_league_level: Map.get(traded_minor, "minorLeagueLevel"),
      minor_team: Map.get(traded_minor, "minorTeam"),
      name: Map.get(traded_minor, "name"),
      owned_by: Map.get(traded_minor, "ownerTeam"),
      position: Map.get(traded_minor, "position"),
      recipient: Map.get(traded_minor, "recipient"),
      sender: Map.get(traded_minor, "sender"),
      trade_id: Map.get(traded_minor, "tradeId")
    }
  end
end
