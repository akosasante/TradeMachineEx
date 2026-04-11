defmodule TradeMachine.Discord.ActionDmEmbed do
  @moduledoc """
  Pure functions that build Discord embed maps for trade action DMs.

  Side-effect free and unit-tested; callers resolve `HydratedTrade` / DB data
  before invoking these functions.
  """

  @embed_color 0x3498DB

  @doc """
  Embed for a trade request (accept / decline links).
  """
  @spec build_request_embed(String.t(), [String.t()], String.t(), String.t()) :: map()
  def build_request_embed(creator, recipients, accept_url, decline_url)
      when is_binary(creator) and is_list(recipients) and is_binary(accept_url) and
             is_binary(decline_url) do
    title =
      if length(recipients) == 1 do
        "#{creator} requested a trade with you"
      else
        "#{creator} requested a trade with you and others"
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

  @doc """
  Embed prompting the creator to submit after recipients accepted.
  """
  @spec build_submit_embed([String.t()], String.t()) :: map()
  def build_submit_embed(recipients, submit_url)
      when is_list(recipients) and is_binary(submit_url) do
    recipient_count = length(recipients)

    title =
      if recipient_count == 1 do
        "#{hd(recipients)} accepted your trade proposal"
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

  @doc """
  Embed for a declined trade. `declined_by` may be nil (shown as \"Someone\").
  `view_url` may be nil or empty to omit the link line.
  """
  @spec build_declined_embed(String.t() | nil, boolean(), String.t() | nil) :: map()
  def build_declined_embed(declined_by, is_creator, view_url)
      when is_boolean(is_creator) do
    decliner = declined_by || "Someone"

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
