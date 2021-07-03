defmodule TradeMachine.Data.HydratedMajors do
  use TradeMachine.Schema

  schema "hydrated_majors" do
    field :name, :string
    field :league,
          Ecto.Enum,
          values: [
            major: "1",
            minor: "2"
          ]
    field :mlb_team, :string #TODO: check inclusion at changeset cast
    field :owner_team, :map
    field :eligible_positions, {:array, TradeMachine.Data.Types.EligiblePositions}
    field :main_position, :string
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
