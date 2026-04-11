defmodule TradeMachine.Data.HydratedTradeCsvDisplay do
  @moduledoc false

  import Ecto.Query

  alias TradeMachine.Data.{HydratedTrade, TeamCsvLabel, TradeItem, TradeParticipant}

  @doc """
  Returns `hydrated` with `creator`, `recipients`, and per-item sender/recipient (and pick
  owner fields) rewritten using each team's csv name when available.

  Requires `repo.all/1` (Ecto.Repo). If the repo does not implement `all/1`, or lookups
  return no rows, the original hydrated row is returned unchanged.
  """
  @spec apply(HydratedTrade.t(), Ecto.UUID.t(), module()) :: HydratedTrade.t()
  def apply(%HydratedTrade{} = h, trade_id, repo) do
    if function_exported?(repo, :all, 1) do
      do_apply(h, trade_id, repo)
    else
      h
    end
  end

  defp do_apply(%HydratedTrade{} = h, trade_id, repo) do
    player_map = trade_item_endpoints(repo, trade_id, :player)
    pick_map = trade_item_endpoints(repo, trade_id, :pick)

    team_ids =
      []
      |> Kernel.++(endpoint_team_ids(player_map))
      |> Kernel.++(endpoint_team_ids(pick_map))
      |> Kernel.++(participant_team_ids(repo, trade_id))
      |> Kernel.++(nested_owner_team_ids(h))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    labels = TeamCsvLabel.labels_by_team_id(team_ids, repo)

    {creator, recipients} = creator_and_recipients(h, trade_id, labels, repo)

    majors = Enum.map(h.traded_majors || [], &relabel_player_row(&1, player_map, labels))
    minors = Enum.map(h.traded_minors || [], &relabel_player_row(&1, player_map, labels))
    picks = Enum.map(h.traded_picks || [], &relabel_pick_row(&1, pick_map, labels))

    %HydratedTrade{
      h
      | creator: creator,
        recipients: recipients,
        traded_majors: majors,
        traded_minors: minors,
        traded_picks: picks
    }
  end

  defp trade_item_endpoints(repo, trade_id, :player) do
    from(ti in TradeItem,
      where: ti.trade_id == ^trade_id and ti.trade_item_type == :player,
      select: {ti.trade_item_id, ti.senderId, ti.recipientId}
    )
    |> repo.all()
    |> Map.new(fn {item_id, sid, rid} -> {id_key(item_id), {sid, rid}} end)
  end

  defp trade_item_endpoints(repo, trade_id, :pick) do
    from(ti in TradeItem,
      where: ti.trade_id == ^trade_id and ti.trade_item_type == :pick,
      select: {ti.trade_item_id, ti.senderId, ti.recipientId}
    )
    |> repo.all()
    |> Map.new(fn {item_id, sid, rid} -> {id_key(item_id), {sid, rid}} end)
  end

  defp endpoint_team_ids(map) do
    map
    |> Map.values()
    |> Enum.flat_map(fn {sid, rid} -> [sid, rid] end)
  end

  defp participant_team_ids(repo, trade_id) do
    from(tp in TradeParticipant,
      where: tp.trade_id == ^trade_id,
      select: tp.team_id
    )
    |> repo.all()
  end

  defp nested_owner_team_ids(%HydratedTrade{
         traded_majors: majors,
         traded_minors: minors,
         traded_picks: picks
       }) do
    rows = (majors || []) ++ (minors || []) ++ (picks || [])

    Enum.flat_map(rows, fn row ->
      owned = Map.get(row, :owned_by) || Map.get(row, "owned_by")
      orig = Map.get(row, :original_owner) || Map.get(row, "original_owner")

      [owner_id_from_value(owned), owner_id_from_value(orig)]
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp owner_id_from_value(%{"id" => id}), do: id
  defp owner_id_from_value(%{id: id}), do: id
  defp owner_id_from_value(_), do: nil

  defp creator_and_recipients(h, trade_id, labels, repo) do
    rows =
      from(tp in TradeParticipant,
        where: tp.trade_id == ^trade_id,
        select: {tp.participant_type, tp.team_id}
      )
      |> repo.all()

    creator =
      case Enum.find(rows, fn {pt, _} -> pt == :creator end) do
        {_, tid} -> Map.get(labels, id_key(tid), h.creator)
        nil -> h.creator
      end

    recipient_labels =
      rows
      |> Enum.filter(fn {pt, _} -> pt == :recipient end)
      |> Enum.map(fn {_, tid} -> Map.get(labels, id_key(tid)) end)
      |> Enum.reject(&is_nil/1)

    recipients = if recipient_labels == [], do: h.recipients, else: recipient_labels

    {creator, recipients}
  end

  defp relabel_player_row(row, player_map, labels) do
    item_id = Map.get(row, :id) || Map.get(row, "id")

    case Map.get(player_map, id_key(item_id)) do
      {sid, rid} ->
        row
        |> put_row(:sender, label_for(labels, sid, row_value(row, :sender, "sender")))
        |> put_row(:recipient, label_for(labels, rid, row_value(row, :recipient, "recipient")))

      _ ->
        row
    end
  end

  defp relabel_pick_row(row, pick_map, labels) do
    item_id = Map.get(row, :id) || Map.get(row, "id")

    row =
      case Map.get(pick_map, id_key(item_id)) do
        {sid, rid} ->
          row
          |> put_row(:sender, label_for(labels, sid, row_value(row, :sender, "sender")))
          |> put_row(:recipient, label_for(labels, rid, row_value(row, :recipient, "recipient")))

        _ ->
          row
      end

    row
    |> put_row(
      :original_owner,
      relabel_owner_field(row_value(row, :original_owner, "original_owner"), labels)
    )
    |> put_row(:owned_by, relabel_owner_field(row_value(row, :owned_by, "owned_by"), labels))
  end

  defp row_value(row, akey, skey), do: Map.get(row, akey) || Map.get(row, skey)

  defp put_row(row, key, value), do: Map.put(row, key, value)

  defp relabel_owner_field(%{"id" => id} = m, labels) do
    fb = Map.get(m, "name")
    Map.get(labels, id_key(id), fb || "Unknown")
  end

  defp relabel_owner_field(%{id: id} = m, labels) do
    fb = Map.get(m, :name) || Map.get(m, "name")
    Map.get(labels, id_key(id), fb || "Unknown")
  end

  defp relabel_owner_field(bin, _labels) when is_binary(bin), do: bin
  defp relabel_owner_field(_, _labels), do: nil

  defp label_for(labels, team_id, fallback) do
    Map.get(labels, id_key(team_id), fallback)
  end

  defp id_key(nil), do: nil
  defp id_key(id) when is_binary(id), do: id
  defp id_key(id), do: to_string(id)
end
