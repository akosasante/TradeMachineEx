defmodule TradeMachine.Discord.CommandRouter do
  @moduledoc """
  Registers Discord slash commands and dispatches interactions to handlers.

  Commands are registered per-guild (instant propagation). Each command declares
  which guild pools it uses — `:staging` guilds from `DISCORD_STAGING_GUILD_IDS`,
  `:production` guilds from `DISCORD_PRODUCTION_GUILD_IDS` (comma-separated snowflakes).
  """

  require Logger

  alias TradeMachine.Discord.Commands.MyTrades
  alias TradeMachine.Discord.Commands.TradeHistory
  alias TradeMachine.Discord.Runtime

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

  # `guild_scopes`: where this command is registered (staging guild list, production list, or both).
  @commands [
    %{definition: @my_trades_command, guild_scopes: [:staging, :production]},
    %{definition: @trade_history_command, guild_scopes: [:staging, :production]}
  ]

  @doc """
  Registers guild-scoped slash commands. Called on the READY event.
  """
  @spec register_commands(Nostrum.Snowflake.t()) :: :ok
  def register_commands(app_id) do
    staging_ids = Application.get_env(:trade_machine, :discord_staging_guild_ids) || []
    prod_ids = Application.get_env(:trade_machine, :discord_production_guild_ids) || []

    registrations =
      @commands
      |> Enum.flat_map(fn spec ->
        for guild_id <- guild_ids_for_scopes(spec.guild_scopes, staging_ids, prod_ids) do
          {guild_id, spec.definition}
        end
      end)
      |> Enum.uniq_by(fn {guild_id, command} -> {guild_id, command.name} end)

    case registrations do
      [] ->
        Logger.warning(
          "No Discord guild targets for slash commands — set DISCORD_STAGING_GUILD_IDS " <>
            "and/or DISCORD_PRODUCTION_GUILD_IDS (comma-separated) so they match each command's guild_scopes; skipping registration"
        )

        :ok

      list ->
        distinct_guilds = list |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

        Logger.info(
          "Registering slash commands on #{length(distinct_guilds)} guild(s) (app #{app_id})"
        )

        for {guild_id, command} <- list do
          case Runtime.application_command_api().create_guild_command(guild_id, command) do
            {:ok, _cmd} ->
              Logger.info("Registered /#{command.name} on guild #{guild_id}")

            {:error, reason} ->
              Logger.error(
                "Failed to register /#{command.name} on guild #{guild_id}: #{inspect(reason)}"
              )
          end
        end

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

    Runtime.interaction_api().create_response(interaction, %{
      type: 4,
      data: %{content: "Unknown command.", flags: 64}
    })
  end

  @spec guild_ids_for_scopes([:staging | :production], [integer()], [integer()]) :: [integer()]
  defp guild_ids_for_scopes(scopes, staging_ids, prod_ids) do
    scopes
    |> Enum.flat_map(fn
      :staging -> staging_ids
      :production -> prod_ids
    end)
    |> Enum.uniq()
  end
end
