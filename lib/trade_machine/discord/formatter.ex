defmodule TradeMachine.Discord.Formatter do
  @moduledoc """
  Pure formatting functions for Discord trade announcements.

  Converts raw trade data into display strings using CSV names
  and the `[Level - MLB Team - Position]` suffix format with
  smart omissions for missing data.

  All functions are side-effect free and suitable for unit testing.
  """

  @typedoc "Represents a resolved trade item ready for formatting"
  @type trade_item ::
          %{
            type: :major_player,
            name: String.t(),
            mlb_team: String.t() | nil,
            position: String.t() | nil
          }
          | %{
              type: :minor_player,
              name: String.t(),
              level: :high | :low | nil,
              mlb_team: String.t() | nil,
              position: String.t() | nil
            }
          | %{
              type: :pick,
              owner_name: String.t(),
              round: Decimal.t() | integer(),
              pick_type: :majors | :high | :low,
              season: integer()
            }

  @typedoc "A participant with resolved display name and items"
  @type participant :: %{
          display_name: String.t(),
          items: [trade_item()]
        }

  @doc """
  Formats a single trade item as a markdown bullet line.

  ## Examples

      iex> format_item(%{type: :major_player, name: "Ketel Marte", mlb_team: "ARI", position: "2B"})
      "• **Ketel Marte** (Majors - ARI - 2B)"

      iex> format_item(%{type: :minor_player, name: "Patrick Forbes", level: nil, mlb_team: nil, position: nil})
      "• **Patrick Forbes** (Minors)"

      iex> format_item(%{type: :pick, owner_name: "Ryan", round: 2, pick_type: :majors, season: 2026})
      "• **Ryan's** 2nd round Major League pick"
  """
  @spec format_item(trade_item()) :: String.t()
  def format_item(item = %{type: :major_player}) do
    suffix = build_suffix(["Majors", item.mlb_team, item.position])
    "• **#{item.name}**#{suffix}"
  end

  def format_item(item = %{type: :minor_player}) do
    level_text = format_minor_level(item.level)
    suffix = build_suffix([level_text, item.mlb_team, item.position])
    "• **#{item.name}**#{suffix}"
  end

  def format_item(item = %{type: :pick}) do
    league_text = format_pick_league(item.pick_type)
    round_text = format_ordinal(item.round)
    "• **#{item.owner_name}'s** #{round_text} round #{league_text} pick"
  end

  @doc """
  Formats all items for a participant as a single string with newline-separated bullet lines.
  """
  @spec format_items([trade_item()]) :: String.t()
  def format_items([]), do: "_No items_"

  def format_items(items) do
    items
    |> Enum.map(&format_item/1)
    |> Enum.join("\n")
  end

  @doc """
  Determines the display name for a team's owners using CSV name style.
  Falls back to team name if no csv_name is available.

  ## Examples

      iex> format_participant_name([%{csv_name: "Ryan"}], "The Mad King")
      "Ryan"

      iex> format_participant_name([%{csv_name: nil}], "The Mad King")
      "The Mad King"
  """
  @spec format_participant_name([map()], String.t()) :: String.t()
  def format_participant_name(owners, team_name) do
    owners
    |> Enum.find_value(fn owner -> Map.get(owner, :csv_name) end)
    |> case do
      nil -> team_name
      csv_name -> csv_name
    end
  end

  @doc """
  Formats owner references as Discord mentions when discord_user_id is available,
  falling back to @display_name.
  """
  @spec format_mentions([map()]) :: String.t()
  def format_mentions(owners) do
    discord_mentions =
      owners
      |> Enum.filter(&Map.get(&1, :discord_user_id))
      |> Enum.map(&"<@#{&1.discord_user_id}>")

    if discord_mentions != [] do
      Enum.join(discord_mentions, ", ")
    else
      owners
      |> Enum.map(&"@#{&1.display_name}")
      |> Enum.join(", ")
    end
  end

  @doc """
  Formats a round number as an ordinal string.

  Handles both integer and Decimal inputs.

  ## Examples

      iex> format_ordinal(1)
      "1st"
      iex> format_ordinal(Decimal.new(3))
      "3rd"
  """
  @spec format_ordinal(Decimal.t() | integer()) :: String.t()
  def format_ordinal(round = %Decimal{}), do: round |> Decimal.to_integer() |> format_ordinal()
  def format_ordinal(1), do: "1st"
  def format_ordinal(2), do: "2nd"
  def format_ordinal(3), do: "3rd"
  def format_ordinal(n) when is_integer(n), do: "#{n}th"

  @doc """
  Formats the draft pick league type as a human-readable string.
  """
  @spec format_pick_league(:majors | :high | :low | atom()) :: String.t()
  def format_pick_league(:majors), do: "Major League"
  def format_pick_league(:high), do: "High Minors"
  def format_pick_league(:low), do: "Low Minors"
  def format_pick_league(_other), do: "Minor League"

  @doc """
  Formats the minor league level as a display string.
  Returns "Minors" for nil/unknown levels.
  """
  @spec format_minor_level(:high | :low | nil) :: String.t()
  def format_minor_level(:high), do: "High Minors"
  def format_minor_level(:low), do: "Low Minors"
  def format_minor_level(nil), do: "Minors"

  # Builds a parenthetical suffix from available (non-nil) parts.
  # Returns empty string if no parts are available.
  @spec build_suffix([String.t() | nil]) :: String.t()
  defp build_suffix(parts) do
    available = Enum.reject(parts, &is_nil/1)

    case available do
      [] -> ""
      parts -> " (#{Enum.join(parts, " - ")})"
    end
  end
end
