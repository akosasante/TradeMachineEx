defmodule TradeMachine.Data.HydratedTrade do
  use TradeMachine.Schema

  import Ecto.Query

  @primary_key false

  alias TradeMachine.Data.Types.TradedMajor
  alias TradeMachine.Data.Types.TradedMinor
  alias TradeMachine.Data.Types.TradedPick

  typed_schema "hydrated_trades" do
    field :trade_id, Ecto.UUID, null: false
    field :date_created, :naive_datetime

    field(:status, Ecto.Enum,
      values: [
        draft: "1",
        requested: "2",
        pending: "3",
        accepted: "4",
        rejected: "5",
        submitted: "6"
      ],
      source: :tradeStatus,
      null: false
    )

    field(:creator, :string, source: :tradeCreator, null: false)
    field(:recipients, {:array, :string}, source: :tradeRecipients, null: false)
    field :declined_by, :string, source: :decliningUser
    field :declined_reason, :string
    field :accepted_by, {:array, :string}, source: :acceptingUsers
    field :accepted_on_date, :naive_datetime
    field :traded_majors, {:array, TradedMajor}
    field :traded_minors, {:array, TradedMinor}
    field :traded_picks, {:array, TradedPick}
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end

  @doc """
  Fetches the hydrated trade row for a given trade_id.
  Returns nil if not found.
  """
  @spec get_by_trade_id(String.t(), Ecto.Repo.t()) :: t() | nil
  def get_by_trade_id(trade_id, repo) do
    repo.one(from(h in __MODULE__, where: h.trade_id == ^trade_id))
  end
end
