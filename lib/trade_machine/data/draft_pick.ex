defmodule TradeMachine.Data.DraftPick do
  use TradeMachine.Schema

  alias TradeMachine.Data.Team

  schema "draft_pick" do
    field :season, :integer
    field :type, Ecto.Enum, values: [majors: "1", high: "2", low: "3"]
    field :round, :decimal # TODO: Maybe decimal? Maybe eventually only allow integers?
    field :pick_number, :integer

    belongs_to :owned_by, Team, source: :currentOwnerId, foreign_key: :currentOwnerId
    belongs_to :original_owner, Team, source: :originalOwnerId, foreign_key: :originalOwnerId

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
