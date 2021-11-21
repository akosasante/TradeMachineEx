defmodule TradeMachine.Data.Types.TradedMajor do
  use Ecto.Type

  alias TradeMachine.Data.Types.EligiblePositions

  def type, do: :map

  # Provide custom casting rules.
  # Cast map into string-keyed map to be inserted into db
  def cast(traded_majors) when is_list(traded_majors) or is_map(traded_majors) do
    {:ok, parse(traded_majors)}
  end

  # Everything else is a failure though
  def cast(_), do: :error

  # When loading data from the database, convert string-keyed map into atom-keyed
  def load(traded_majors) when is_list(traded_majors) or is_map(traded_majors) do
    {:ok, load_majors(traded_majors)}
  end

  # When dumping data to the database, we *expect* a string-keyed map
  # but any value could be inserted into the schema struct at runtime,
  # so we need to guard against them.
  def dump(traded_majors) when is_list(traded_majors) do
    if Enum.all?(traded_majors, fn {k, _} -> is_binary(k) end) do
      {:ok, traded_majors}
    else
      :error
    end
  end

  def dump(_), do: :error

  defp parse(traded_majors) when is_list(traded_majors) do
    Enum.map(traded_majors, &parse/1)
  end

  defp parse(traded_major) when is_map(traded_major) do
    {:ok, eligible_positions} = EligiblePositions.cast(Map.get(traded_major, :eligible_positions))

    %{
      "eligiblePositions" => eligible_positions,
      "id" => Map.get(traded_major, :id),
      "league" => Map.get(traded_major, :league),
      "mainPosition" => Map.get(traded_major, :main_position),
      "mlbTeam" => Map.get(traded_major, :mlb_team),
      "name" => Map.get(traded_major, :name),
      "ownerTeam" => Map.get(traded_major, :owned_by),
      "recipient" => Map.get(traded_major, :recipient),
      "sender" => Map.get(traded_major, :sender),
      "tradeId" => Map.get(traded_major, :trade_id)
    }
  end

  defp load_majors(traded_majors) when is_list(traded_majors) do
    Enum.map(traded_majors, &load_majors/1)
  end

  defp load_majors(traded_major) when is_map(traded_major) do
    {:ok, eligible_positions} = EligiblePositions.load(Map.get(traded_major, "eligiblePositions"))

    %{
      eligible_positions: eligible_positions,
      id: Map.get(traded_major, "id"),
      league: Map.get(traded_major, "league"),
      main_position: Map.get(traded_major, "mainPosition"),
      mlb_team: Map.get(traded_major, "mlbTeam"),
      name: Map.get(traded_major, "name"),
      owned_by: Map.get(traded_major, "ownerTeam"),
      recipient: Map.get(traded_major, "recipient"),
      sender: Map.get(traded_major, "sender"),
      trade_id: Map.get(traded_major, "tradeId")
    }
  end
end
