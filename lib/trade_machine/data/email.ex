defmodule TradeMachine.Data.Email do
  use TradeMachine.Schema

  alias TradeMachine.Data.Trade

  @primary_key {:message_id, :string, autogenerate: false}

  typed_schema "email" do
    field :status, :string, null: false

    belongs_to :trade, Trade

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
