defmodule TradeMachine.Discord.Announcer do
  @moduledoc """
  Orchestrates Discord trade announcement flow.

  Public API for announcing trades to Discord. Handles fetching trade data
  from the database, resolving player and draft pick details, formatting
  the announcement, and sending it via the Discord client.

  ## Usage

      # Announce a trade in the production environment
      TradeMachine.Discord.Announcer.announce_trade("trade-uuid", :production)

      # Announce a trade in staging
      TradeMachine.Discord.Announcer.announce_trade("trade-uuid", :staging)

  ## Testing in IEx

      # Build the embed without sending (for inspection)
      {:ok, embed} = TradeMachine.Discord.Announcer.build_announcement("trade-uuid", :staging)
      IO.inspect(embed, pretty: true)

      # Send to a specific channel for testing
      {:ok, embed} = TradeMachine.Discord.Announcer.build_announcement("trade-uuid", :staging)
      TradeMachine.Discord.Client.send_embed(993_941_280_184_864_928, embed)
  """

  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.HydratedMajor
  alias TradeMachine.Data.HydratedMinor
  alias TradeMachine.Data.Trade
  alias TradeMachine.Discord.Client
  alias TradeMachine.Discord.EmbedBuilder
  alias TradeMachine.Discord.Formatter

  import Ecto.Query

  require Logger

  @doc """
  Announces a trade to Discord.

  Fetches the trade from the database, builds the announcement embed,
  and sends it to the appropriate Discord channel.

  ## Parameters
    - `trade_id` - UUID of the trade to announce
    - `environment` - `:production` or `:staging`

  ## Returns
    - `{:ok, message}` on success
    - `{:error, reason}` on failure
  """
  @spec announce_trade(String.t(), :production | :staging) ::
          {:ok, map()} | {:error, term()}
  def announce_trade(trade_id, environment) do
    with {:ok, embed} <- build_announcement(trade_id, environment) do
      Client.send_trade_announcement(embed, environment)
    end
  end

  @doc """
  Builds the announcement embed without sending it.
  Useful for testing and inspecting the output.
  """
  @spec build_announcement(String.t(), :production | :staging) ::
          {:ok, map()} | {:error, term()}
  def build_announcement(trade_id, environment) do
    repo = select_repo(environment)

    with {:ok, trade} <- fetch_trade(trade_id, repo),
         {:ok, trade_data} <- resolve_trade_data(trade, repo) do
      embed = EmbedBuilder.build_trade_embed(trade_data)
      {:ok, embed}
    end
  end

  defp select_repo(:production), do: TradeMachine.Repo.Production
  defp select_repo(:staging), do: TradeMachine.Repo.Staging

  defp fetch_trade(trade_id, repo) do
    trade =
      repo.get(Trade, trade_id)
      |> repo.preload(
        participants: [team: :current_owners],
        traded_items: [:sender, :recipient],
        creator: [team: :current_owners],
        recipients: [team: :current_owners]
      )

    case trade do
      nil ->
        Logger.error("Trade not found: #{trade_id}")
        {:error, :trade_not_found}

      trade ->
        {:ok, trade}
    end
  end

  defp resolve_trade_data(trade, repo) do
    player_item_ids = extract_item_ids(trade.traded_items, :player)
    pick_item_ids = extract_item_ids(trade.traded_items, :pick)

    players_by_id = fetch_hydrated_players(player_item_ids, repo)
    picks_by_id = fetch_draft_picks(pick_item_ids, repo)

    participants_by_team_id = index_participants(trade)

    resolved_participants =
      trade.participants
      |> Enum.map(fn participant ->
        team_id = participant.team.id
        received_items = items_received_by(trade.traded_items, team_id)

        items =
          Enum.map(received_items, fn item ->
            resolve_item(item, players_by_id, picks_by_id, participants_by_team_id)
          end)

        owners = participant.team.current_owners
        team_name = participant.team.name

        %{
          display_name: Formatter.format_participant_name(owners, team_name),
          items: items
        }
      end)

    creator_owners = trade.creator.team.current_owners

    recipient_owners =
      trade.recipients
      |> Enum.flat_map(fn r -> r.team.current_owners end)

    trade_data = %{
      trade_id: trade.id,
      date_created: trade.inserted_at |> to_utc_datetime(),
      creator: %{owners: creator_owners},
      recipient_owners: recipient_owners,
      participants: resolved_participants
    }

    {:ok, trade_data}
  end

  defp extract_item_ids(trade_items, type) do
    trade_items
    |> Enum.filter(&(&1.trade_item_type == type))
    |> Enum.map(& &1.trade_item_id)
    |> Enum.uniq()
  end

  defp items_received_by(trade_items, team_id) do
    Enum.filter(trade_items, fn item ->
      item.recipient && item.recipient.id == team_id
    end)
  end

  defp fetch_hydrated_players([], _repo), do: %{}

  defp fetch_hydrated_players(player_ids, repo) do
    majors =
      repo.all(from(m in HydratedMajor, where: m.id in ^player_ids))
      |> Enum.map(fn m ->
        {m.id,
         %{
           type: :major_player,
           name: m.name,
           mlb_team: m.mlb_team,
           position: m.main_position
         }}
      end)

    found_major_ids = Enum.map(majors, fn {id, _} -> id end)
    remaining_ids = player_ids -- found_major_ids

    minors =
      repo.all(from(m in HydratedMinor, where: m.id in ^remaining_ids))
      |> Enum.map(fn m ->
        {m.id,
         %{
           type: :minor_player,
           name: m.name,
           level: m.minor_league_level,
           mlb_team: m.minor_team,
           position: m.position
         }}
      end)

    Map.new(majors ++ minors)
  end

  defp fetch_draft_picks([], _repo), do: %{}

  defp fetch_draft_picks(pick_ids, repo) do
    repo.all(
      from(p in DraftPick,
        where: p.id in ^pick_ids,
        preload: [original_owner: :current_owners]
      )
    )
    |> Map.new(fn pick -> {pick.id, pick} end)
  end

  defp index_participants(trade) do
    all_participant_entries =
      [trade.creator | trade.recipients]
      |> Enum.map(fn p -> {p.team.id, p.team} end)

    Map.new(all_participant_entries)
  end

  defp resolve_item(trade_item, players_by_id, picks_by_id, participants_by_team_id) do
    case trade_item.trade_item_type do
      :player ->
        resolve_player_item(trade_item.trade_item_id, players_by_id)

      :pick ->
        resolve_pick_item(trade_item.trade_item_id, picks_by_id, participants_by_team_id)
    end
  end

  defp resolve_player_item(player_id, players_by_id) do
    case Map.get(players_by_id, player_id) do
      nil ->
        %{type: :major_player, name: "Unknown Player", mlb_team: nil, position: nil}

      player_data ->
        player_data
    end
  end

  defp resolve_pick_item(pick_id, picks_by_id, participants_by_team_id) do
    case Map.get(picks_by_id, pick_id) do
      nil ->
        %{type: :pick, owner_name: "Unknown", round: 0, pick_type: :majors, season: 0}

      pick ->
        original_owner_team = pick.original_owner
        owner_name = resolve_pick_owner_name(original_owner_team, participants_by_team_id)

        %{
          type: :pick,
          owner_name: owner_name,
          round: pick.round,
          pick_type: pick.type,
          season: pick.season
        }
    end
  end

  defp resolve_pick_owner_name(nil, _participants_by_team_id), do: "Unknown"

  defp resolve_pick_owner_name(team, participants_by_team_id) do
    resolved_team = Map.get(participants_by_team_id, team.id, team)
    owners = resolved_team.current_owners

    if Ecto.assoc_loaded?(owners) && owners != [] do
      Formatter.format_participant_name(owners, team.name)
    else
      team.name
    end
  end

  defp to_utc_datetime(ndt = %NaiveDateTime{}) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp to_utc_datetime(dt = %DateTime{}), do: dt
end
