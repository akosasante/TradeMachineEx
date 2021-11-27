defmodule TradeMachine.Data.TradeItem do
  use TradeMachine.Schema

  alias TradeMachine.Data.Team
  alias TradeMachine.Data.Trade

  schema "trade_item" do
    field :trade_item_type, Ecto.Enum, values: [player: "1", pick: "2"]
    field :trade_item_id, Ecto.UUID

    belongs_to :sender, Team, source: :senderId, foreign_key: :senderId
    belongs_to :recipient, Team, source: :recipientId, foreign_key: :recipientId
    belongs_to :trade, Trade

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [:trade_item_type, :trade_item_id, :senderId, :recipientId])
    |> cast_assoc(:sender)
    |> cast_assoc(:recipient)
  end
end
