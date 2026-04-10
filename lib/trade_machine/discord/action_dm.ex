defmodule TradeMachine.Discord.ActionDm do
  @moduledoc """
  Builds embeds and sends Discord DMs for trade workflow notifications (request, submit, declined).

  Mirrors trade email copy where practical; URLs are precomputed by the TypeScript server.
  """

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.User
  alias TradeMachine.Discord.Client

  require Logger

  @embed_color 0x3498DB

  @spec send_trade_request_dm(String.t(), String.t(), String.t(), String.t(), Ecto.Repo.t()) ::
          {:ok, map()} | {:error, term()}
  def send_trade_request_dm(trade_id, recipient_user_id, accept_url, decline_url, repo) do
    with {:ok, hydrated} <- fetch_hydrated_trade(trade_id, repo),
         {:ok, discord_id} <- discord_id_for_user(recipient_user_id, repo) do
      embed = build_request_embed(hydrated, accept_url, decline_url)
      Client.send_dm_embed(discord_id, embed)
    end
  end

  @spec send_trade_submit_dm(String.t(), String.t(), String.t(), Ecto.Repo.t()) ::
          {:ok, map()} | {:error, term()}
  def send_trade_submit_dm(trade_id, recipient_user_id, submit_url, repo) do
    with {:ok, hydrated} <- fetch_hydrated_trade(trade_id, repo),
         {:ok, discord_id} <- discord_id_for_user(recipient_user_id, repo) do
      embed = build_submit_embed(hydrated, submit_url)
      Client.send_dm_embed(discord_id, embed)
    end
  end

  @spec send_trade_declined_dm(String.t(), String.t(), boolean(), String.t() | nil, Ecto.Repo.t()) ::
          {:ok, map()} | {:error, term()}
  def send_trade_declined_dm(trade_id, recipient_user_id, is_creator, view_url, repo) do
    with {:ok, hydrated} <- fetch_hydrated_trade(trade_id, repo),
         {:ok, discord_id} <- discord_id_for_user(recipient_user_id, repo) do
      embed = build_declined_embed(hydrated, is_creator, view_url)
      Client.send_dm_embed(discord_id, embed)
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

      %User{discord_user_id: raw} when is_binary(raw) ->
        case String.trim(raw) do
          "" ->
            Logger.info("Skipping Discord DM: user has no discord_user_id",
              recipient_user_id: recipient_user_id
            )

            {:error, :no_discord_user_id}

          id ->
            {:ok, id}
        end

      _ ->
        Logger.info("Skipping Discord DM: user has no discord_user_id",
          recipient_user_id: recipient_user_id
        )

        {:error, :no_discord_user_id}
    end
  end

  defp build_request_embed(hydrated, accept_url, decline_url) do
    title =
      if length(hydrated.recipients) == 1 do
        "#{hydrated.creator} requested a trade with you"
      else
        "#{hydrated.creator} requested a trade with you and others"
      end

    description = """
    **#{title}**

    [Accept](#{accept_url}) · [Decline](#{decline_url})
    """

    %{
      title: "TradeMachine — action needed",
      description: String.trim(description),
      color: @embed_color
    }
  end

  defp build_submit_embed(hydrated, submit_url) do
    recipient_count = length(hydrated.recipients)

    title =
      if recipient_count == 1 do
        "#{hd(hydrated.recipients)} accepted your trade proposal"
      else
        "Recipients accepted your trade proposal"
      end

    description = """
    **#{title}**

    Submit the trade to the league: [Submit trade](#{submit_url})
    """

    %{
      title: "TradeMachine — submit your trade",
      description: String.trim(description),
      color: @embed_color
    }
  end

  defp build_declined_embed(hydrated, is_creator, view_url) do
    decliner = hydrated.declined_by || "Someone"

    title_text =
      if is_creator do
        "Your trade proposal was declined by #{decliner}"
      else
        "A trade you were part of was declined by #{decliner}"
      end

    description =
      case view_url do
        url when is_binary(url) and url != "" ->
          """
          **#{title_text}**

          [View trade](#{url})
          """

        _ ->
          """
          **#{title_text}**
          """
      end

    %{
      title: "TradeMachine — trade declined",
      description: String.trim(description),
      color: @embed_color
    }
  end
end
