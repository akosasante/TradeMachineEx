defmodule TradeMachine.Data.HydratedMinor do
  use TradeMachine.Schema

  typed_schema "hydrated_minors" do
    field :name, :string, null: false

    field(
      :league,
      Ecto.Enum,
      values: [
        minor: "2"
      ],
      null: false
    )

    # TODO: check inclusion at changeset cast
    field :minor_team, :string
    field :owner_team, :map
    field :minor_league_level, Ecto.Enum, values: [high: "High", low: "Low"]
    field :position, :string
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
