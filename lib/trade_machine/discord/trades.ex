defmodule TradeMachine.Discord.Trades do
  @moduledoc """
  Trade query functions for Discord slash commands.

  Provides lookups for mapping Discord users to TradeMachine users
  and fetching recent trades by team membership.
  """

  import Ecto.Query

  alias TradeMachine.Data.Trade
  alias TradeMachine.Data.TradeParticipant
  alias TradeMachine.Data.User

  @max_results 5

  @active_statuses [:requested, :pending, :accepted]
  @closed_statuses [:rejected, :submitted]

  @doc """
  Looks up a TradeMachine user by their Discord snowflake ID.
  Returns `nil` if no user is linked to that Discord account.
  """
  @spec find_user_by_discord_id(String.t(), Ecto.Repo.t()) :: User.t() | nil
  def find_user_by_discord_id(discord_id, repo \\ TradeMachine.Repo.Production) do
    repo.get_by(User, discord_user_id: discord_id)
  end

  @doc """
  Returns the trade statuses corresponding to a filter name.

  - `"active"` -> requested, pending, accepted
  - `"closed"` -> rejected, submitted
  - `"all"` / `nil` -> all statuses (no filter)
  """
  @spec statuses_for_filter(String.t() | nil) :: [atom()] | nil
  def statuses_for_filter("active"), do: @active_statuses
  def statuses_for_filter("closed"), do: @closed_statuses
  def statuses_for_filter(_), do: nil

  @doc """
  Counts all trades matching the given filters for a team.

  ## Options

    * `:statuses` - list of trade status atoms to filter by; `nil` means all
    * `:repo` - Ecto repo to query (default: `TradeMachine.Repo.Production`)

  """
  @spec count_trades_for_team(String.t(), keyword()) :: non_neg_integer()
  def count_trades_for_team(team_id, opts \\ []) do
    statuses = Keyword.get(opts, :statuses)
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)

    base =
      from(t in Trade,
        join: tp in TradeParticipant,
        on: tp.trade_id == t.id,
        where: tp.team_id == ^team_id
      )

    query =
      if statuses do
        where(base, [t], t.status in ^statuses)
      else
        base
      end

    repo.aggregate(query, :count)
  end

  @doc """
  Fetches the most recent trades (up to #{@max_results}) for a given team.

  ## Options

    * `:statuses` - list of trade status atoms to filter by; `nil` means all
    * `:repo` - Ecto repo to query (default: `TradeMachine.Repo.Production`)

  """
  @spec list_recent_trades_for_team(String.t(), keyword()) :: [Trade.t()]
  def list_recent_trades_for_team(team_id, opts \\ []) do
    statuses = Keyword.get(opts, :statuses)
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)

    base =
      from(t in Trade,
        join: tp in TradeParticipant,
        on: tp.trade_id == t.id,
        where: tp.team_id == ^team_id,
        order_by: [desc: t.inserted_at],
        limit: @max_results
      )

    query =
      if statuses do
        where(base, [t], t.status in ^statuses)
      else
        base
      end

    query
    |> repo.all()
    |> repo.preload(
      participants: [team: :current_owners],
      traded_items: [:sender, :recipient]
    )
  end
end
