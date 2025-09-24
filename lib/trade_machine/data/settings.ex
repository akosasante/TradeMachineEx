defmodule TradeMachine.Data.Settings do
  use TradeMachine.Schema

  alias TradeMachine.Data.User

  typed_schema "settings" do
    field :trade_window_start, :time
    field :trade_window_end, :time
    field :downtime, :map

    belongs_to :modified_by, User

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
