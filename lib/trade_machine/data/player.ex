defmodule TradeMachine.Data.Player do
  use TradeMachine.Schema

  alias TradeMachine.Data.Team

  @required_fields [:name, :league]
  @optional_fields [:mlb_team, :player_data_id, :meta, :leagueTeamId]

  typed_schema "player" do
    field(:name, :string, null: false)

    field(
      :league,
      Ecto.Enum,
      values: [
        major: "1",
        minor: "2"
      ],
      null: false
    )

    field(:mlb_team, :string)
    field(:player_data_id, :integer)
    field(:meta, :map, load_in_query: false)
    field(:last_synced_at, :utc_datetime_usec)

    belongs_to(:owned_by, Team, source: :leagueTeamId, foreign_key: :leagueTeamId)

    timestamps()
  end

  def new(params \\ %{}) do
    changeset(%__MODULE__{}, params)
  end

  def changeset(struct = %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
