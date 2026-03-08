defmodule TradeMachine.Discord.Client do
  @moduledoc """
  Thin wrapper around the Discord API for sending messages.

  Handles channel ID selection based on environment and provides
  a consistent interface for sending embeds to Discord channels.
  """

  require Logger

  @doc """
  Sends a trade announcement embed to the appropriate Discord channel.

  The channel is determined by the environment:
  - `:production` uses `DISCORD_CHANNEL_ID_PRODUCTION`
  - `:staging` uses `DISCORD_CHANNEL_ID_STAGING`

  Returns `{:ok, message}` on success or `{:error, reason}` on failure.
  """
  @spec send_trade_announcement(map(), :production | :staging) ::
          {:ok, map()} | {:error, term()}
  def send_trade_announcement(embed, environment) do
    case channel_id(environment) do
      nil ->
        Logger.error("Discord channel ID not configured for #{environment}")
        {:error, :channel_not_configured}

      channel_id ->
        send_embed(channel_id, embed)
    end
  end

  @doc """
  Sends an embed to a specific channel ID. Useful for testing with a custom channel.
  """
  @spec send_embed(integer(), map()) :: {:ok, map()} | {:error, term()}
  def send_embed(channel_id, embed) do
    Logger.info("Sending trade announcement to Discord channel #{channel_id}")

    # content: "" is required for Discord to resolve <@userId> mentions in the
    # embed description; without a content field present, mentions render as raw "<@id>" text.
    case Nostrum.Api.Message.create(channel_id, content: "", embeds: [embed]) do
      {:ok, message} ->
        Logger.info("Trade announcement sent successfully (message_id: #{message.id})")
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to send trade announcement: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the Discord channel ID for the given environment.
  """
  @spec channel_id(:production | :staging) :: integer() | nil
  def channel_id(environment) do
    env_var =
      case environment do
        :production -> "DISCORD_CHANNEL_ID_PRODUCTION"
        :staging -> "DISCORD_CHANNEL_ID_STAGING"
      end

    case System.get_env(env_var) do
      nil -> nil
      "" -> nil
      id_str -> String.to_integer(id_str)
    end
  end
end
