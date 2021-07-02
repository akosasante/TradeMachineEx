defmodule TradeMachine.Data.User do
  use TradeMachine.Schema

  alias TradeMachine.Data.Team

  schema "user" do
    field :display_name, :string
    field :email, :string
    field :status, Ecto.Enum, values: [active: "1", inactive: "2"]
    field :slack_username, :string
    field :csv_name, :string
    field :role, Ecto.Enum, values: [admin: "1", owner: "2", commissioner: "3"]
    field :espn_member, :map, load_in_query: false
    field :last_logged_in, :naive_datetime
    field :password, :string, redact: true, load_in_query: false
    field :password_reset_expires_on, :string, load_in_query: false
    field :password_reset_token, :string, load_in_query: false

    belongs_to :current_team, Team, source: :teamId, foreign_key: :teamId
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
