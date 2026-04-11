defmodule TradeMachine.Discord.ActionDmEmbed do
  @moduledoc """
  Pure functions that build Discord embed maps and message components for trade action DMs.

  Side-effect free and unit-tested; callers resolve `HydratedTrade` / DB data
  before invoking these functions.

  Accept / decline / submit use Discord **link** buttons (style 5) so actions are
  prominent; URLs are still supplied by the TypeScript server.
  """

  @embed_color 0x3498DB

  @doc """
  Action row with **Accept** and **Decline** link buttons (opens the pre-auth URLs in the browser).
  """
  @spec request_action_components(String.t(), String.t()) :: [map()]
  def request_action_components(accept_url, decline_url)
      when is_binary(accept_url) and is_binary(decline_url) do
    [
      %{
        type: 1,
        components: [
          %{type: 2, style: 5, label: "Accept", url: accept_url},
          %{type: 2, style: 5, label: "Decline", url: decline_url}
        ]
      }
    ]
  end

  @doc """
  Action row with a single **Submit trade** link button.
  """
  @spec submit_action_components(String.t()) :: [map()]
  def submit_action_components(submit_url) when is_binary(submit_url) do
    [
      %{
        type: 1,
        components: [
          %{type: 2, style: 5, label: "Submit trade", url: submit_url}
        ]
      }
    ]
  end

  @doc """
  Optional action row with **View trade** link button. Returns `[]` when URL is empty.
  """
  @spec declined_action_components(String.t() | nil) :: [map()]
  def declined_action_components(url) when url in [nil, ""], do: []

  def declined_action_components(url) when is_binary(url) do
    [
      %{
        type: 1,
        components: [
          %{type: 2, style: 5, label: "View trade", url: url}
        ]
      }
    ]
  end

  @doc """
  Embed for a trade request. Use `request_action_components/2` for Accept / Decline buttons.

  `fields` should come from `ActionDmTradeSummary.embed_fields_for_items/3`.
  """
  @spec build_request_embed(String.t(), [String.t()], [map()]) :: map()
  def build_request_embed(creator, recipients, fields \\ [])
      when is_binary(creator) and is_list(recipients) and is_list(fields) do
    title =
      if length(recipients) == 1 do
        "#{creator} requested a trade with you"
      else
        "#{creator} requested a trade with you and others"
      end

    description = """
    **#{title}**

    Review what each team would receive below, then use **Accept** or **Decline**.
    """

    base = %{
      title: "TradeMachine — action needed",
      description: String.trim(description),
      color: @embed_color
    }

    if fields == [] do
      base
    else
      Map.put(base, :fields, fields)
    end
  end

  @doc """
  Embed prompting the creator to submit after recipients accepted.
  """
  @spec build_submit_embed([String.t()], [map()]) :: map()
  def build_submit_embed(recipients, fields \\ [])
      when is_list(recipients) and is_list(fields) do
    recipient_count = length(recipients)

    title =
      if recipient_count == 1 do
        "#{hd(recipients)} accepted your trade proposal"
      else
        "Recipients accepted your trade proposal"
      end

    description = """
    **#{title}**

    When you are ready, submit the trade to the league using the button below.
    """

    base = %{
      title: "TradeMachine — submit your trade",
      description: String.trim(description),
      color: @embed_color
    }

    if fields == [] do
      base
    else
      Map.put(base, :fields, fields)
    end
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

          Open the trade in TradeMachine with the button below if you want the full picture.
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
