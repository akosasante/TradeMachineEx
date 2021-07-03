defmodule TradeMachine.Data.Types.TradedPick do
  use Ecto.Type

  def type, do: :map

  # Provide custom casting rules.
  # Cast map into string-keyed map to be inserted into db
  def cast(traded_picks) when is_list(traded_picks) or is_map(traded_picks) do
    {:ok, parse(traded_picks)}
  end

  # Everything else is a failure though
  def cast(_), do: :error

  # When loading data from the database, convert string-keyed map into atom-keyed
  def load(traded_picks) when is_list(traded_picks) or is_map(traded_picks) do
    {:ok, load_picks(traded_picks)}
  end

  # When dumping data to the database, we *expect* a string-keyed map
  # but any value could be inserted into the schema struct at runtime,
  # so we need to guard against them.
  def dump(traded_picks) when is_list(traded_picks) do
    if Enum.all?(traded_picks, fn {k, _} -> is_binary(k) end) do
      {:ok, traded_picks}
    else
      :error
    end
  end

  def dump(_), do: :error

  defp parse(traded_picks) when is_list(traded_picks) do
    Enum.map(traded_picks, &parse/1)
  end

  defp parse(traded_pick) when is_map(traded_pick) do
    %{
      "id" => Map.get(traded_pick, :id),
      "currentPickHolder" => Map.get(traded_pick, :owned_by),
      "originalPickOwner" => Map.get(traded_pick, :original_owner),
      "pickNumber" => Map.get(traded_pick, :pick_number),
      "round" => Map.get(traded_pick, :round),
      "season" => Map.get(traded_pick, :season),
      "type" => Map.get(traded_pick, :type),
      "recipient" => Map.get(traded_pick, :recipient),
      "sender" => Map.get(traded_pick, :sender),
      "tradeId" => Map.get(traded_pick, :trade_id)
    }
  end

  defp load_picks(traded_picks) when is_list(traded_picks) do
    Enum.map(traded_picks, &load_picks/1)
  end

  defp load_picks(traded_pick) when is_map(traded_pick) do
    %{
      id: Map.get(traded_pick, "id"),
      owned_by: Map.get(traded_pick, "currentPickHolder"),
      original_owner: Map.get(traded_pick, "originalPickOwner"),
      pick_number: Map.get(traded_pick, "pickNumber"),
      round: Map.get(traded_pick, "round"),
      season: Map.get(traded_pick, "season"),
      type:  Map.get(traded_pick, "type"),
      recipient: Map.get(traded_pick, "recipient"),
      sender: Map.get(traded_pick, "sender"),
      trade_id: Map.get(traded_pick, "tradeId")
    }
  end
end
