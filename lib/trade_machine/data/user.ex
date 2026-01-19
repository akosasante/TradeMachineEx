defmodule TradeMachine.Data.User do
  use TradeMachine.Schema

  alias TradeMachine.Data.Team
  alias TradeMachine.Data.Trade
  require Logger
  require Ecto.Query
  import Ecto.Query

  @derive {Swoosh.Email.Recipient, name: :display_name, address: :email}

  typed_schema "user" do
    field(:display_name, :string, null: false)
    field(:email, :string, null: false)
    field(:status, Ecto.Enum, values: [active: "1", inactive: "2"], null: false)
    field :slack_username, :string
    field :csv_name, :string
    field(:role, Ecto.Enum, values: [admin: "1", owner: "2", commissioner: "3"], null: false)
    field :espn_member, :map, load_in_query: false
    field :last_logged_in, :naive_datetime
    field :password, :string, redact: true, load_in_query: false
    field :password_reset_expires_on, :naive_datetime, load_in_query: false
    field :password_reset_token, :string, load_in_query: false

    belongs_to :current_team, Team, source: :teamId, foreign_key: :teamId
    has_many :declined_trades, Trade, foreign_key: :declinedById

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end

  def get_by_id(id, repo \\ TradeMachine.Repo.Production) when is_binary(id) do
    repo.get(__MODULE__, id)
  end

  @spec get_by_id_with_password_reset_token(String.t(), Ecto.Repo.t()) ::
          __MODULE__.t() | nil
  def get_by_id_with_password_reset_token(id, repo \\ TradeMachine.Repo.Production)
      when is_binary(id) do
    from(u in __MODULE__,
      where: u.id == ^id,
      select: %__MODULE__{
        id: u.id,
        display_name: u.display_name,
        email: u.email,
        status: u.status,
        role: u.role,
        password_reset_token: u.password_reset_token,
        inserted_at: u.inserted_at,
        updated_at: u.updated_at
      }
    )
    |> repo.one()
  end

  @spec get_user_by_csv_name(String.t(), Ecto.Repo.t()) :: __MODULE__.t() | nil
  def get_user_by_csv_name(csv_name, repo \\ TradeMachine.Repo.Production) do
    repo.get_by(__MODULE__, csv_name: csv_name)
  end

  @spec get_user_team_id(keyword(), Ecto.Repo.t()) :: String.t() | nil
  def get_user_team_id(by_tuple, repo \\ TradeMachine.Repo.Production) do
    __MODULE__
    |> repo.get_by(by_tuple)
    |> case do
      %__MODULE__{teamId: team_id} ->
        team_id

      nil ->
        Logger.error("Could not find user with this query: #{inspect(by_tuple)}")
        nil
    end
  end
end
