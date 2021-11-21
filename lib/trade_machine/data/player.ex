defmodule TradeMachine.Data.Player do
  use TradeMachine.Schema

  alias TradeMachine.Data.Team

  schema "player" do
    field :name, :string
    field :league, Ecto.Enum, values: [major: "1", minor: "2"]
    # TODO: check inclusion at changeset cast
    field :mlb_team, :string
    field :player_data_id, :integer
    field :meta, :map, load_in_query: false

    belongs_to :owned_by, Team, source: :leagueTeamId, foreign_key: :leagueTeamId

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
