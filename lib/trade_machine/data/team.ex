defmodule TradeMachine.Data.Team do
  use TradeMachine.Schema

  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.Player
  alias TradeMachine.Data.User

  schema "team" do
    field :name, :string
    field :espn_id, :integer
    field :status, Ecto.Enum, values: [active: "1", disabled: "2"]
    field :espn_team, :map, load_in_query: false

    has_many :owned_picks, DraftPick, foreign_key: :currentOwnerId
    has_many :owned_players, Player, foreign_key: :leagueTeamId
    has_many :original_picks, DraftPick, foreign_key: :originalOwnerId
    has_many :current_owners, User, foreign_key: :teamId

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
