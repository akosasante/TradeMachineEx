defmodule TradeMachine.Data.DraftPick do
  use TradeMachine.Schema

  schema "draft_pick" do
    field :round, :decimal # TODO: Maybe decimal? Maybe eventually only allow integers?
    field :pick_number, :integer
    field :season, :integer
    field :type, Ecto.Enum, values: [majors: "1", high: "2", low: "3"]
    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
