defmodule TradeMachine.Data.DraftPick do
  use TradeMachine.Schema

  alias TradeMachine.Data.Team

  require Ecto.Query

  @required_fields [:round, :season, :type]
  @optional_fields [:pick_number, :currentOwnerId, :originalOwnerId]

  typed_schema "draft_pick" do
    field :season, :integer, null: false

    field(
      :type,
      Ecto.Enum,
      values: [
        majors: "1",
        high: "2",
        low: "3"
      ],
      null: false
    )

    # TODO: Maybe decimal? Maybe eventually only allow integers?
    field :round, :decimal, null: false
    field :pick_number, :integer

    belongs_to :owned_by, Team, source: :currentOwnerId, foreign_key: :currentOwnerId
    belongs_to :original_owner, Team, source: :originalOwnerId, foreign_key: :originalOwnerId

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
