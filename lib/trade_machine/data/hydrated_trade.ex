defmodule TradeMachine.Data.HydratedTrade do
  use TradeMachine.Schema

  @primary_key false

  alias TradeMachine.Data.Types.TradedMajor
  alias TradeMachine.Data.Types.TradedMinor
  alias TradeMachine.Data.Types.TradedPick

  schema "hydrated_trades" do
    field :trade_id, Ecto.UUID
    field :date_created, :naive_datetime
    field :status, Ecto.Enum, values: [draft: "1", requested: "2", pending: "3", accepted: "4", rejected: "5", submitted: "6"], source: :tradeStatus
    field :creator, :string, source: :tradeCreator
    field :recipients, {:array, :string}, source: :tradeRecipients
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
end
