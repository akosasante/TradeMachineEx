defmodule TradeMachine.Discord.TradeListEmbedBuilder do
  @moduledoc """
  Builds compact Discord embeds for listing a user's trades.

  Unlike the announcement `EmbedBuilder`, these are designed for ephemeral
  slash command responses: concise, with deep links to the V3 web app.
  """

  alias TradeMachine.Data.HydratedMajor
  alias TradeMachine.Data.HydratedMinor
  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.Trade
  alias TradeMachine.Discord.Formatter

  import Ecto.Query

  @embed_color 0x3498DB
  @description_char_limit 4096
  @truncation_buffer 120

  @status_labels %{
    draft: "Draft",
    requested: "Requested",
    pending: "Pending",
    accepted: "Accepted",
    rejected: "Declined",
    submitted: "Submitted"
  }

  @doc """
  Builds an embed for a list of trades shown to `display_name`.
  Returns a map compatible with Nostrum embed format.

  Automatically truncates trade entries if the description would exceed
  Discord's 4096-character embed description limit.
  """
  @spec build(String.t(), [Trade.t()], keyword()) :: map()
  def build(title, trades, opts \\ []) do
    frontend_url = Keyword.get(opts, :frontend_url, "")
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)
    user_team_id = Keyword.get(opts, :user_team_id)
    total_count = Keyword.get(opts, :total_count)

    web_link =
      if frontend_url != "" do
        "#{frontend_url}/my-trades"
      else
        nil
      end

    {description, entries_shown} =
      if Enum.empty?(trades) do
        {"_No trades found._", 0}
      else
        safe_limit = @description_char_limit - @truncation_buffer
        join_trade_entries(trades, safe_limit, frontend_url, repo, user_team_id)
      end

    not_shown = length(trades) - entries_shown
    not_shown_from_query = if total_count, do: total_count - entries_shown, else: not_shown

    footer_text =
      case {not_shown_from_query > 0, web_link} do
        {true, nil} -> "and #{not_shown_from_query} more — view all on the trades app"
        {true, url} -> "and #{not_shown_from_query} more — view all at #{url}"
        {false, nil} -> "View more on the trades app"
        {false, url} -> "View all trades at #{url}"
      end

    %{
      title: title,
      description: description,
      color: @embed_color,
      footer: %{text: footer_text}
    }
  end

  defp join_trade_entries(trades, safe_limit, frontend_url, repo, user_team_id) do
    trades
    |> Enum.with_index(1)
    |> Enum.reduce_while({[], 0, 0}, fn {trade, idx}, state ->
      append_trade_entry(trade, idx, state, safe_limit, frontend_url, repo, user_team_id)
    end)
    |> then(fn {entries, count, _chars} ->
      {Enum.join(entries, "\n\n"), count}
    end)
  end

  defp append_trade_entry(
         trade,
         idx,
         {entries, count, chars},
         safe_limit,
         frontend_url,
         repo,
         user_team_id
       ) do
    entry = format_trade_entry(trade, idx, frontend_url, repo, user_team_id)
    separator = if entries == [], do: 0, else: 2
    new_chars = chars + separator + String.length(entry)

    if new_chars > safe_limit and entries != [] do
      {:halt, {entries, count, chars}}
    else
      {:cont, {entries ++ [entry], count + 1, new_chars}}
    end
  end

  defp format_trade_entry(trade, idx, frontend_url, repo, user_team_id) do
    status_label = Map.get(@status_labels, trade.status, "Unknown")

    timestamp = trade.inserted_at |> NaiveDateTime.to_erl() |> erl_to_unix()
    time_text = "<t:#{timestamp}:R>"

    participants_text = format_participants_summary(trade, repo, user_team_id)

    link_text =
      if frontend_url != "" do
        "[View trade](#{frontend_url}/trades/#{trade.id}/review)"
      else
        ""
      end

    lines =
      [
        "#{idx}. #{status_label} | #{time_text}",
        participants_text,
        link_text
      ]
      |> Enum.reject(&(&1 == ""))

    Enum.join(lines, "\n")
  end

  defp format_participants_summary(trade, repo, user_team_id) do
    trade.participants
    |> Enum.map(fn participant ->
      team = participant.team
      team_name = Formatter.format_participant_name(team.current_owners, team.name)

      {display_name, verb} =
        if user_team_id && team.id == user_team_id do
          {"You", "get"}
        else
          {team_name, "gets"}
        end

      items_received = items_for_team(trade.traded_items, team.id)
      item_names = resolve_item_names(items_received, repo)

      items_text =
        case item_names do
          [] -> "_nothing_"
          names -> Enum.join(names, ", ")
        end

      "#{display_name} #{verb}: #{items_text}"
    end)
    |> Enum.join("\n")
  end

  defp items_for_team(trade_items, team_id) do
    Enum.filter(trade_items, fn item ->
      item.recipient && item.recipientId == team_id
    end)
  end

  defp resolve_item_names(items, repo) do
    {player_items, pick_items} =
      Enum.split_with(items, &(&1.trade_item_type == :player))

    player_ids = Enum.map(player_items, & &1.trade_item_id)
    pick_ids = Enum.map(pick_items, & &1.trade_item_id)

    player_names = resolve_player_names(player_ids, repo)
    pick_names = resolve_pick_names(pick_ids, repo)

    player_names ++ pick_names
  end

  defp resolve_player_names([], _repo), do: []

  defp resolve_player_names(player_ids, repo) do
    majors =
      repo.all(from(m in HydratedMajor, where: m.id in ^player_ids, select: {m.id, m.name}))

    found_ids = Enum.map(majors, fn {id, _} -> id end)
    remaining = player_ids -- found_ids

    minors =
      repo.all(from(m in HydratedMinor, where: m.id in ^remaining, select: {m.id, m.name}))

    (majors ++ minors)
    |> Enum.map(fn {_id, name} -> name end)
  end

  defp resolve_pick_names([], _repo), do: []

  defp resolve_pick_names(pick_ids, repo) do
    picks =
      repo.all(
        from(p in DraftPick,
          where: p.id in ^pick_ids,
          preload: [:original_owner]
        )
      )

    Enum.map(picks, fn pick ->
      round_text = Formatter.format_ordinal(pick.round)
      league_text = Formatter.format_pick_league(pick.type)

      owner_name =
        if pick.original_owner do
          Formatter.format_participant_name([], pick.original_owner.name)
        else
          "Unknown"
        end

      "#{owner_name}'s #{round_text} #{league_text} pick"
    end)
  end

  defp erl_to_unix({{y, mo, d}, {h, mi, s}}) do
    NaiveDateTime.new!(y, mo, d, h, mi, s)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end
end
