defmodule TradeMachine.Discord.Commands.MyTrades do
  @moduledoc """
  Handler for the `/my-trades` slash command.

  Shows the caller's active/pending trades (statuses: requested, pending, accepted).
  Responses are ephemeral -- only the invoking user can see them.
  """

  require Logger

  alias TradeMachine.Discord.TradeListEmbedBuilder
  alias TradeMachine.Discord.Trades

  def handle(interaction) do
    discord_id = to_string(interaction.member.user_id)

    case Trades.find_user_by_discord_id(discord_id) do
      nil ->
        respond_ephemeral(
          interaction,
          "Your Discord account isn't linked to a TradeMachine account."
        )

      %{teamId: nil} ->
        respond_ephemeral(interaction, "You don't have a team assigned in TradeMachine.")

      user ->
        statuses = Trades.statuses_for_filter("active")

        trades =
          Trades.list_recent_trades_for_team(user.teamId, statuses: statuses)

        total_count =
          Trades.count_trades_for_team(user.teamId, statuses: statuses)

        frontend_url = Application.get_env(:trade_machine, :frontend_url_production) || ""

        embed =
          TradeListEmbedBuilder.build(
            "Your Active Trades",
            trades,
            frontend_url: frontend_url,
            user_team_id: user.teamId,
            total_count: total_count
          )

        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{embeds: [embed], flags: 64}
        })
    end
  end

  defp respond_ephemeral(interaction, message) do
    Nostrum.Api.Interaction.create_response(interaction, %{
      type: 4,
      data: %{content: message, flags: 64}
    })
  end
end
