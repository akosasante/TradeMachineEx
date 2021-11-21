defmodule TradeMachine.Data.HydratedMajor do
  use TradeMachine.Schema

  alias TradeMachine.Data.Types.EligiblePositions

  schema "hydrated_majors" do
    field :name, :string

    field :league,
          Ecto.Enum,
          values: [
            major: "1",
            minor: "2"
          ]

    # TODO: check inclusion at changeset cast
    field :mlb_team, :string
    field :owner_team, :map
    field :eligible_positions, {:array, EligiblePositions}
    field :main_position, :string
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
