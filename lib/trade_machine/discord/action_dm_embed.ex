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

  `view_url` may be nil or empty to omit the **View trade** hint (link buttons still
  come from `declined_action_components/1`).

  ## Options

    * `:trade_id` — UUID string; shown in the embed footer so the recipient can tell
      which trade this was.
    * `:declined_reason` — optional free-text reason from the decliner; truncated for length.

  """
  @spec build_declined_embed(String.t() | nil, boolean(), String.t() | nil, keyword()) :: map()
  def build_declined_embed(declined_by, is_creator, view_url, opts \\ [])
      when is_boolean(is_creator) and is_list(opts) do
    decliner = declined_by || "Someone"
    trade_id = trade_id_opt(Keyword.get(opts, :trade_id))
    reason = declined_reason_opt(Keyword.get(opts, :declined_reason))

    title_text =
      if is_creator do
        "Your trade proposal was declined by #{decliner}"
      else
        "A trade you were part of was declined by #{decliner}"
      end

    reason_section =
      case reason do
        nil ->
          ""

        text ->
          "\n\n**Decline reason**\n#{text}\n"
      end

    view_section =
      case view_url do
        url when is_binary(url) ->
          if String.trim(url) != "" do
            "\n\nOpen the trade in your browser with **View trade** below."
          else
            no_url_hint(trade_id)
          end

        _ ->
          no_url_hint(trade_id)
      end

    description =
      """
      **#{title_text}**#{reason_section}#{view_section}
      """
      |> String.trim()

    base = %{
      title: "TradeMachine — trade declined",
      description: description,
      color: @embed_color
    }

    case footer_for_trade_id(trade_id) do
      nil -> base
      footer -> Map.put(base, :footer, footer)
    end
  end

  defp trade_id_opt(tid) when is_binary(tid) do
    case String.trim(tid) do
      "" -> nil
      t -> t
    end
  end

  defp trade_id_opt(_), do: nil

  defp declined_reason_opt(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" ->
        nil

      t ->
        truncate_reason(t, 450)
    end
  end

  defp declined_reason_opt(_), do: nil

  defp truncate_reason(text, max) do
    if String.length(text) <= max do
      text
    else
      String.slice(text, 0..(max - 2)) <> "…"
    end
  end

  defp no_url_hint(nil), do: ""

  defp no_url_hint(_trade_id) do
    "\n\nIf you are not sure which proposal this was, use the **trade ID** in the footer to look it up in TradeMachine."
  end

  defp footer_for_trade_id(nil), do: nil

  defp footer_for_trade_id(tid) when is_binary(tid) do
    %{text: "Trade ID: #{tid}"}
  end
end
