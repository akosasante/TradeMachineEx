defmodule TradeMachine.Data.Types.EligiblePositions do
  use Ecto.Type

  @eligible_positions_map %{
    0 => "C",
    1 => "1B",
    2 => "2B",
    3 => "3B",
    4 => "SS",
    5 => "OF",
    6 => "2B/SS",
    7 => "1B/3B",
    8 => "LF",
    9 => "CF",
    10 => "RF",
    11 => "DH",
    12 => "UTIL",
    13 => "P",
    14 => "SP",
    15 => "RP",
    16 => "BE",
    17 => "IL",
    18 => "IF"
  }

  @eligible_positions_str_map Map.new(@eligible_positions_map, fn {k, v} -> {v, k} end)

  def type, do: {:array, :integer}

  # Provide custom casting rules.
  # Cast string positions into integers to be inserted into db
  def cast(eligible_positions) when is_list(eligible_positions) do
    {:ok, parse_string_positions(eligible_positions)}
  end

  # Everything else is a failure though
  def cast(_), do: :error

  # When loading data from the database, convert integers into strings
  def load(eligible_positions_ints)
      when is_list(eligible_positions_ints) or is_integer(eligible_positions_ints) do
    {:ok, get_string_positions(eligible_positions_ints)}
  end

  def load(nil), do: {:ok, nil}

  # When dumping data to the database, we *expect* a list of integers
  # but any value could be inserted into the schema struct at runtime,
  # so we need to guard against them.
  def dump(eligible_positions) when is_list(eligible_positions) do
    if Enum.all?(eligible_positions, fn position -> is_integer(position) end) do
      {:ok, eligible_positions}
    else
      :error
    end
  end

  def dump(_), do: :error

  defp parse_string_positions(eligible_positions_strings)
       when is_list(eligible_positions_strings) do
    Enum.map(eligible_positions_strings, &parse_string_positions/1)
  end

  defp parse_string_positions(eligible_positions_string)
       when is_binary(eligible_positions_string) do
    Map.get(@eligible_positions_str_map, eligible_positions_string, :unknown_position)
  end

  defp get_string_positions(eligible_positions_ints) when is_list(eligible_positions_ints) do
    eligible_positions_ints
    |> Enum.map(&get_string_positions/1)
    |> Enum.reject(&is_nil/1)
  end

  defp get_string_positions(eligible_positions_int) when is_integer(eligible_positions_int) do
    Map.get(@eligible_positions_map, eligible_positions_int)
  end
end
