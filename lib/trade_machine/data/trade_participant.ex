defmodule TradeMachine.Data.TradeParticipant do
  use TradeMachine.Schema

  alias TradeMachine.Data.Trade
  alias TradeMachine.Data.Team

  schema "trade_participant" do
    field :participant_type, Ecto.Enum, values: [creator: "1", recipient: "2"]

    belongs_to :trade, Trade
    belongs_to :team, Team

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [:participant_type, :team_id, :trade_id])
  end
end
