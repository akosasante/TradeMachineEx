defmodule TradeMachine.Data.HydratedPick do
  use TradeMachine.Schema

  typed_schema "hydrated_picks" do
    field :season, :integer, null: false
    field(:type, Ecto.Enum, values: [majors: "1", high: "2", low: "3"], null: false)
    # TODO: Maybe decimal? Maybe eventually only allow integers?
    field :round, :decimal, null: false
    field :pick_number, :integer
    field :owned_by, :map, source: :currentPickHolder
    field :original_owner, :map, source: :originalPickOwner
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
