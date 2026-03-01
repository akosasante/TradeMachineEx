defmodule TradeMachine.ESPN.Constants do
  @moduledoc """
  ESPN API constants for MLB teams and player positions.

  Ported from TradeMachineServer/src/espn/espnConstants.ts to keep
  both codebases consistent.
  """

  @pro_team_by_id %{
    0 => %{abbrev: "FA", location: "", name: "FA"},
    1 => %{abbrev: "Bal", location: "Baltimore", name: "Orioles"},
    2 => %{abbrev: "Bos", location: "Boston", name: "Red Sox"},
    3 => %{abbrev: "LAA", location: "Los Angeles", name: "Angels"},
    4 => %{abbrev: "ChW", location: "Chicago", name: "White Sox"},
    5 => %{abbrev: "Cle", location: "Cleveland", name: "Indians"},
    6 => %{abbrev: "Det", location: "Detroit", name: "Tigers"},
    7 => %{abbrev: "KC", location: "Kansas City", name: "Royals"},
    8 => %{abbrev: "Mil", location: "Milwaukee", name: "Brewers"},
    9 => %{abbrev: "Min", location: "Minnesota", name: "Twins"},
    10 => %{abbrev: "NYY", location: "New York", name: "Yankees"},
    11 => %{abbrev: "Oak", location: "Oakland", name: "Athletics"},
    12 => %{abbrev: "Sea", location: "Seattle", name: "Mariners"},
    13 => %{abbrev: "Tex", location: "Texas", name: "Rangers"},
    14 => %{abbrev: "Tor", location: "Toronto", name: "Blue Jays"},
    15 => %{abbrev: "Atl", location: "Atlanta", name: "Braves"},
    16 => %{abbrev: "ChC", location: "Chicago", name: "Cubs"},
    17 => %{abbrev: "Cin", location: "Cincinnati", name: "Reds"},
    18 => %{abbrev: "Hou", location: "Houston", name: "Astros"},
    19 => %{abbrev: "LAD", location: "Los Angeles", name: "Dodgers"},
    20 => %{abbrev: "Wsh", location: "Washington", name: "Nationals"},
    21 => %{abbrev: "NYM", location: "New York", name: "Mets"},
    22 => %{abbrev: "Phi", location: "Philadelphia", name: "Phillies"},
    23 => %{abbrev: "Pit", location: "Pittsburgh", name: "Pirates"},
    24 => %{abbrev: "StL", location: "St. Louis", name: "Cardinals"},
    25 => %{abbrev: "SD", location: "San Diego", name: "Padres"},
    26 => %{abbrev: "SF", location: "San Francisco", name: "Giants"},
    27 => %{abbrev: "Col", location: "Colorado", name: "Rockies"},
    28 => %{abbrev: "Mia", location: "Miami", name: "Marlins"},
    29 => %{abbrev: "Ari", location: "Arizona", name: "Diamondbacks"},
    30 => %{abbrev: "TB", location: "Tampa Bay", name: "Rays"}
  }

  @position_by_id %{
    1 => "SP",
    2 => "C",
    3 => "1B",
    4 => "2B",
    5 => "3B",
    6 => "SS",
    7 => "LF",
    8 => "CF",
    9 => "RF",
    10 => "DH",
    11 => "RP"
  }

  @eligible_position_by_slot %{
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

  @non_positional_slots MapSet.new([5, 6, 7, 11, 12, 13, 16, 17, 18, 19])

  @doc """
  Returns the MLB team abbreviation (uppercased) for the given ESPN `proTeamId`.
  Returns `nil` for unknown IDs or free agents (id 0).
  """
  @spec mlb_team_abbrev(integer()) :: String.t() | nil
  def mlb_team_abbrev(0), do: nil

  def mlb_team_abbrev(pro_team_id) when is_integer(pro_team_id) do
    case Map.get(@pro_team_by_id, pro_team_id) do
      %{abbrev: abbrev} -> String.upcase(abbrev)
      nil -> nil
    end
  end

  def mlb_team_abbrev(_), do: nil

  @doc """
  Returns the full pro team map for the given ESPN `proTeamId`.
  """
  @spec pro_team(integer()) :: map() | nil
  def pro_team(pro_team_id) when is_integer(pro_team_id) do
    Map.get(@pro_team_by_id, pro_team_id)
  end

  def pro_team(_), do: nil

  @doc """
  Returns the default position string (e.g. "SP", "C", "SS") for the given
  ESPN `defaultPositionId`.
  """
  @spec position(integer()) :: String.t() | nil
  def position(position_id) when is_integer(position_id) do
    Map.get(@position_by_id, position_id)
  end

  def position(_), do: nil

  @doc """
  Converts a list of ESPN eligible slot IDs into a comma-separated position string,
  filtering out non-positional slots (BE, IL, UTIL, etc.).
  """
  @spec eligible_positions([integer()]) :: String.t() | nil
  def eligible_positions(slot_ids) when is_list(slot_ids) do
    positions =
      slot_ids
      |> Enum.reject(&MapSet.member?(@non_positional_slots, &1))
      |> Enum.map(&Map.get(@eligible_position_by_slot, &1))
      |> Enum.reject(&is_nil/1)

    case positions do
      [] -> nil
      list -> Enum.join(list, ", ")
    end
  end

  def eligible_positions(_), do: nil
end
