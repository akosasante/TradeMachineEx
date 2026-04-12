defmodule TradeMachine.Discord.ActionDm do
  @moduledoc """
  Builds embeds and sends Discord DMs for trade workflow notifications (request, submit, declined).

  Mirrors trade email copy where practical; URLs are precomputed by the TypeScript server.
  """

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.HydratedTradeCsvDisplay
  alias TradeMachine.Data.User
  alias TradeMachine.Data.UserSettings
  alias TradeMachine.Discord.ActionDmEmbed
  alias TradeMachine.Discord.ActionDmTradeSummary
  alias TradeMachine.Discord.DmSender

  require Logger

  @spec send_trade_request_dm(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          Ecto.Repo.t(),
          String.t() | nil
        ) ::
          {:ok, map()} | {:error, term()}
  def send_trade_request_dm(
        trade_id,
        recipient_user_id,
        accept_url,
        decline_url,
        repo,
        notification_settings_url \\ nil
      ) do
    with {:ok, hydrated} <- fetch_hydrated_trade(trade_id, repo),
         {:ok, discord_id} <- discord_id_for_user(recipient_user_id, repo) do
      hydrated = HydratedTradeCsvDisplay.apply(hydrated, trade_id, repo)

      fields =
        ActionDmTradeSummary.embed_fields_for_items(
          hydrated.traded_majors,
          hydrated.traded_minors,
          hydrated.traded_picks
        )

      embed =
        ActionDmEmbed.build_request_embed(hydrated.creator, hydrated.recipients, fields)
        |> ActionDmEmbed.with_settings_footer(notification_settings_url)

      components = ActionDmEmbed.request_action_components(accept_url, decline_url)
      DmSender.impl().send_dm_embed(discord_id, embed, components)
    end
  end

  @spec send_trade_submit_dm(
          String.t(),
          String.t(),
          String.t(),
          Ecto.Repo.t(),
          String.t() | nil
        ) ::
          {:ok, map()} | {:error, term()}
  def send_trade_submit_dm(
        trade_id,
        recipient_user_id,
        submit_url,
        repo,
        notification_settings_url \\ nil
      ) do
    with {:ok, hydrated} <- fetch_hydrated_trade(trade_id, repo),
         {:ok, discord_id} <- discord_id_for_user(recipient_user_id, repo) do
      hydrated = HydratedTradeCsvDisplay.apply(hydrated, trade_id, repo)

      fields =
        ActionDmTradeSummary.embed_fields_for_items(
          hydrated.traded_majors,
          hydrated.traded_minors,
          hydrated.traded_picks
        )

      embed =
        ActionDmEmbed.build_submit_embed(hydrated.recipients, fields)
        |> ActionDmEmbed.with_settings_footer(notification_settings_url)

      components = ActionDmEmbed.submit_action_components(submit_url)
      DmSender.impl().send_dm_embed(discord_id, embed, components)
    end
  end

  @spec send_trade_declined_dm(
          String.t(),
          String.t(),
          boolean(),
          String.t() | nil,
          Ecto.Repo.t(),
          String.t() | nil
        ) ::
          {:ok, map()} | {:error, term()}
  def send_trade_declined_dm(
        trade_id,
        recipient_user_id,
        is_creator,
        view_url,
        repo,
        notification_settings_url \\ nil
      ) do
    with {:ok, hydrated} <- fetch_hydrated_trade(trade_id, repo),
         {:ok, discord_id} <- discord_id_for_user(recipient_user_id, repo) do
      embed =
        ActionDmEmbed.build_declined_embed(hydrated.declined_by, is_creator, view_url,
          declined_reason: hydrated.declined_reason
        )
        |> ActionDmEmbed.with_settings_footer(notification_settings_url)

      components = ActionDmEmbed.declined_action_components(view_url)
      DmSender.impl().send_dm_embed(discord_id, embed, components)
    end
  end

  defp fetch_hydrated_trade(trade_id, repo) do
    case HydratedTrade.get_by_trade_id(trade_id, repo) do
      nil ->
        Logger.error("Hydrated trade not found for Discord DM", trade_id: trade_id)
        {:error, :trade_not_found}

      h ->
        {:ok, h}
    end
  end

  defp discord_id_for_user(recipient_user_id, repo) do
    case User.get_by_id(recipient_user_id, repo) do
      nil ->
        Logger.error("User not found for Discord DM", recipient_user_id: recipient_user_id)
        {:error, :user_not_found}

      %User{discord_user_id: raw, user_settings: settings} when is_binary(raw) ->
        case String.trim(raw) do
          "" ->
            Logger.info("Skipping Discord DM: user has no discord_user_id",
              recipient_user_id: recipient_user_id
            )

            {:error, :no_discord_user_id}

          id ->
            if UserSettings.discord_dm_enabled?(settings) do
              {:ok, id}
            else
              Logger.info("Skipping Discord DM: user disabled via settings",
                recipient_user_id: recipient_user_id
              )

              {:error, :discord_dm_disabled_by_user}
            end
        end

      _ ->
        Logger.info("Skipping Discord DM: user has no discord_user_id",
          recipient_user_id: recipient_user_id
        )

        {:error, :no_discord_user_id}
    end
  end
end
