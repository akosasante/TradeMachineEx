defmodule TradeMachine.Data.Trade do
  use TradeMachine.Schema

  alias TradeMachine.Data.User
  alias TradeMachine.Data.Email

  schema "trade" do
    field :status, Ecto.Enum, values: [draft: "1", requested: "2", pending: "3", accepted: "4", rejected: "5", submitted: "6"]
    field :declined_reason, :string
    field :accepted_on_date, :naive_datetime
    field :accepted_by, {:array, :string} # TODO: Explicitly populate these via a query or something

    belongs_to :declined_by, User, source: :declinedById, foreign_key: :declinedById
    has_many :emails, Email

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
