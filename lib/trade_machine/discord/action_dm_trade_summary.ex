defmodule TradeMachine.Discord.ActionDmTradeSummary do
  @moduledoc """
  Builds Discord embed fields summarizing trade assets from hydrated trade rows.

  Grouping mirrors `TradeMachine.Mailer.TradeRequestEmail` (by receiving team).
  """

  @max_field_name 256
  @max_field_value 1024
  @max_fields 8

  @doc """
  Returns a list of embed `fields` maps (`name`, `value`, `inline`) for Discord.
  """
  @spec embed_fields_for_items(
          list(map()) | nil,
          list(map()) | nil,
          list(map()) | nil
        ) :: [map()]
  def embed_fields_for_items(traded_majors, traded_minors, traded_picks) do
    majors =
      (traded_majors || [])
      |> Enum.map(fn m -> {recipient_label(m.recipient), "#{m.name} from #{m.sender}"} end)

    minors =
      (traded_minors || [])
      |> Enum.map(fn m -> {recipient_label(m.recipient), "#{m.name} from #{m.sender}"} end)

    picks =
      (traded_picks || [])
      |> Enum.map(fn p -> {recipient_label(p.recipient), format_pick_line(p)} end)

    grouped =
      (majors ++ minors ++ picks)
      |> Enum.group_by(fn {recipient, _} -> recipient end)

    if grouped == %{} do
      [empty_trade_details_field()]
    else
      grouped
      |> Enum.sort_by(fn {team, _} -> team end)
      |> Enum.take(@max_fields)
      |> Enum.map(&recipient_team_embed_field/1)
    end
  end

  defp empty_trade_details_field do
    %{
      name: "Trade details",
      value: "_No player or pick details are available for this trade snapshot._",
      inline: false
    }
  end

  defp recipient_team_embed_field({team, pairs}) do
    body =
      pairs
      |> Enum.map(&elem(&1, 1))
      |> Enum.map(&("• " <> &1))
      |> Enum.join("\n")
      |> truncate_string(@max_field_value)

    %{
      name: truncate_string("Receiving: #{team}", @max_field_name),
      value: body,
      inline: false
    }
  end

  defp recipient_label(nil), do: "Unknown team"
  defp recipient_label(""), do: "Unknown team"
  defp recipient_label(name) when is_binary(name), do: name
  defp recipient_label(_), do: "Unknown team"

  defp format_pick_line(pick) do
    type_str =
      case pick.type do
        "MAJORS" -> "Majors"
        "HIGH" -> "High Minors"
        "LOW" -> "Low Minors"
        t -> to_string(t || "?")
      end

    original_owner =
      (pick.original_owner || pick.owned_by || pick.sender)
      |> team_name()

    round_str = ordinal(pick.round)

    "#{original_owner}'s #{round_str} round #{type_str} pick from #{pick.sender}"
  end

  defp team_name(%{"name" => name}) when is_binary(name), do: name
  defp team_name(name) when is_binary(name), do: name
  defp team_name(nil), do: "Unknown"
  defp team_name(_other), do: "Unknown"

  defp ordinal(n) when is_integer(n) do
    suffix =
      cond do
        rem(n, 100) in [11, 12, 13] -> "th"
        rem(n, 10) == 1 -> "st"
        rem(n, 10) == 2 -> "nd"
        rem(n, 10) == 3 -> "rd"
        true -> "th"
      end

    "#{n}#{suffix}"
  end

  defp ordinal(nil), do: "?"
  defp ordinal(n), do: "#{n}"

  defp truncate_string(str, max) when is_binary(str) and is_integer(max) do
    if String.length(str) <= max do
      str
    else
      String.slice(str, 0, max - 1) <> "…"
    end
  end
end
