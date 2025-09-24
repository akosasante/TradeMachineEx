defmodule TradeMachine.Data.HydratedMajor do
  use TradeMachine.Schema

  alias TradeMachine.Data.Types.EligiblePositions

  typed_schema "hydrated_majors" do
    field :name, :string, null: false

    field(
      :league,
      Ecto.Enum,
      values: [
        major: "1"
      ],
      null: false
    )

    # TODO: check inclusion at changeset cast
    field :mlb_team, :string
    field :owner_team, :map
    field :eligible_positions, EligiblePositions.type()
    field :main_position, :string
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
