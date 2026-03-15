defmodule TradeMachine.Mailer.TradeDeclinedEmail do
  use TradeMachine.Mailer

  require Logger

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.User

  @spec send(String.t(), String.t(), boolean(), String.t() | nil, String.t(), Ecto.Repo.t()) ::
          {:ok, any()} | {:error, any()}
  def send(trade_id, recipient_user_id, is_creator, decline_url, frontend_environment, repo) do
    with hydrated_trade when not is_nil(hydrated_trade) <-
           HydratedTrade.get_by_trade_id(trade_id, repo),
         user when not is_nil(user) <- User.get_by_id(recipient_user_id, repo) do
      generate_email(hydrated_trade, user, is_creator, decline_url, frontend_environment)
      |> do_deliver(frontend_environment, repo, trade_id)
    else
      nil ->
        Logger.error("Trade or user not found for trade declined email",
          trade_id: trade_id,
          recipient_user_id: recipient_user_id
        )

        {:error, :not_found}
    end
  rescue
    e ->
      Logger.error("Database error sending trade declined email",
        trade_id: trade_id,
        error: Exception.message(e)
      )

      {:error, {:db_error, Exception.message(e)}}
  end

  @spec generate_email(HydratedTrade.t(), User.t(), boolean(), String.t() | nil, String.t()) ::
          Swoosh.Email.t()
  def generate_email(hydrated_trade, user, is_creator, decline_url, frontend_environment) do
    to_email =
      if frontend_environment == "production" do
        user.email
      else
        Application.get_env(:trade_machine, :staging_email)
      end

    title_text =
      if is_creator do
        "Your trade proposal was declined by #{hydrated_trade.declined_by}"
      else
        "A trade you were part of was declined by #{hydrated_trade.declined_by}"
      end

    items_by_team = build_items_by_team(hydrated_trade)

    new()
    |> from(from_tuple())
    |> to({user.display_name, to_email})
    |> subject("Trade Declined")
    |> render_body(:trade_declined, %{
      title_text: title_text,
      declined_by: hydrated_trade.declined_by,
      declined_reason: hydrated_trade.declined_reason,
      items_by_team: items_by_team,
      decline_url: decline_url
    })
  end

  defp build_items_by_team(hydrated_trade) do
    majors =
      (hydrated_trade.traded_majors || [])
      |> Enum.map(fn m -> {m.recipient, :major, "#{m.name} from #{m.sender}"} end)

    minors =
      (hydrated_trade.traded_minors || [])
      |> Enum.map(fn m -> {m.recipient, :minor, "#{m.name} from #{m.sender}"} end)

    picks =
      (hydrated_trade.traded_picks || [])
      |> Enum.map(fn p -> {p.recipient, :pick, format_pick(p)} end)

    (majors ++ minors ++ picks)
    |> Enum.group_by(fn {recipient, _type, _desc} -> recipient end)
    |> Enum.map(fn {team, items} ->
      %{
        team: team,
        majors:
          items
          |> Enum.filter(fn {_, type, _} -> type == :major end)
          |> Enum.map(fn {_, _, desc} -> desc end),
        minors:
          items
          |> Enum.filter(fn {_, type, _} -> type == :minor end)
          |> Enum.map(fn {_, _, desc} -> desc end),
        picks:
          items
          |> Enum.filter(fn {_, type, _} -> type == :pick end)
          |> Enum.map(fn {_, _, desc} -> desc end)
      }
    end)
    |> Enum.sort_by(& &1.team)
  end

  defp format_pick(pick) do
    type_str =
      case pick.type do
        "MAJORS" -> "Majors"
        "HIGH" -> "High Minors"
        "LOW" -> "Low Minors"
        t -> t
      end

    original_owner =
      (pick.original_owner || pick.owned_by || pick.sender)
      |> team_name()

    round_str = ordinal(pick.round)

    "#{original_owner}'s #{round_str} round #{type_str} pick from #{pick.sender}"
  end

  defp team_name(%{"name" => name}) when is_binary(name), do: name
  defp team_name(name) when is_binary(name), do: name
  defp team_name(nil), do: "Unknown"
  defp team_name(other), do: inspect(other)

  defp ordinal(n) when is_integer(n) do
    suffix =
      cond do
        rem(n, 100) in [11, 12, 13] -> "th"
        rem(n, 10) == 1 -> "st"
        rem(n, 10) == 2 -> "nd"
        rem(n, 10) == 3 -> "rd"
        true -> "th"
      end

    "#{n}#{suffix}"
  end

  defp ordinal(nil), do: "?"
  defp ordinal(n), do: "#{n}"
end
