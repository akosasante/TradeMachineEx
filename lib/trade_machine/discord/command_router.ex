defmodule TradeMachine.Discord.CommandRouter do
  @moduledoc """
  Registers Discord slash commands and dispatches interactions to handlers.

  Commands are registered per-guild (instant propagation) using `DISCORD_GUILD_ID`.
  """

  require Logger

  alias TradeMachine.Discord.Commands.MyTrades
  alias TradeMachine.Discord.Commands.TradeHistory

  @my_trades_command %{
    name: "my-trades",
    description: "List your pending and active trades"
  }

  @trade_history_command %{
    name: "trade-history",
    description: "Your last 5 trades (see the web app for more)",
    options: [
      %{
        type: 3,
        name: "status",
        description: "Filter by status (default: all)",
        choices: [
          %{name: "Active", value: "active"},
          %{name: "Closed", value: "closed"},
          %{name: "All", value: "all"}
        ]
      }
    ]
  }

  @doc """
  Registers guild-scoped slash commands. Called on the READY event.
  """
  @spec register_commands(Nostrum.Snowflake.t()) :: :ok
  def register_commands(app_id) do
    guild_id = guild_id()

    if guild_id do
      Logger.info("Registering slash commands for guild #{guild_id} (app #{app_id})")

      for command <- [@my_trades_command, @trade_history_command] do
        case Nostrum.Api.ApplicationCommand.create_guild_command(guild_id, command) do
          {:ok, _cmd} ->
            Logger.info("Registered /#{command.name}")

          {:error, reason} ->
            Logger.error("Failed to register /#{command.name}: #{inspect(reason)}")
        end
      end

      :ok
    else
      Logger.warning("DISCORD_GUILD_ID not set — skipping slash command registration")
      :ok
    end
  end

  @doc """
  Dispatches an interaction to the appropriate command handler.
  """
  def handle(interaction = %{data: %{name: "my-trades"}}) do
    MyTrades.handle(interaction)
  end

  def handle(interaction = %{data: %{name: "trade-history"}}) do
    TradeHistory.handle(interaction)
  end

  def handle(interaction) do
    Logger.warning("Unknown command: #{inspect(interaction.data.name)}")

    Nostrum.Api.Interaction.create_response(interaction, %{
      type: 4,
      data: %{content: "Unknown command.", flags: 64}
    })
  end

  defp guild_id do
    case Application.get_env(:trade_machine, :discord_guild_id) do
      nil -> nil
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
    end
  end
end
