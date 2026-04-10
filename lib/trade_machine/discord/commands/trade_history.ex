defmodule TradeMachine.Discord.Commands.TradeHistory do
  @moduledoc """
  Handler for the `/trade-history` slash command.

  Shows the caller's last 5 trades with an optional status filter,
  plus deep links to each trade's review page on the V3 web app.
  Responses are ephemeral.
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
        status_filter = extract_option(interaction, "status")
        statuses = Trades.statuses_for_filter(status_filter)

        trades = Trades.list_recent_trades_for_team(user.teamId, statuses: statuses)

        total_count =
          Trades.count_trades_for_team(user.teamId, statuses: statuses)

        frontend_url = Application.get_env(:trade_machine, :frontend_url_production) || ""

        title =
          case status_filter do
            "active" -> "Your Last 5 Active Trades"
            "closed" -> "Your Last 5 Closed Trades"
            _ -> "Your Last 5 Trades"
          end

        embed =
          TradeListEmbedBuilder.build(
            title,
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

  defp extract_option(interaction, name) do
    case interaction.data.options do
      nil ->
        nil

      options ->
        options
        |> Enum.find(fn opt -> opt.name == name end)
        |> case do
          nil -> nil
          opt -> opt.value
        end
    end
  end

  defp respond_ephemeral(interaction, message) do
    Nostrum.Api.Interaction.create_response(interaction, %{
      type: 4,
      data: %{content: message, flags: 64}
    })
  end
end
