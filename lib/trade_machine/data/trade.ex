defmodule TradeMachine.Data.Trade do
  use TradeMachine.Schema

  alias TradeMachine.Data.User
  alias TradeMachine.Data.Email
  alias TradeMachine.Data.TradeParticipant
  alias TradeMachine.Data.TradeItem
  alias TradeMachine.Data.Player
  alias TradeMachine.Data.DraftPick
  
  schema "trade" do
    field :status,
          Ecto.Enum,
          values: [
            draft: "1",
            requested: "2",
            pending: "3",
            accepted: "4",
            rejected: "5",
            submitted: "6"
          ]

    field :declined_reason, :string
    field :accepted_on_date, :naive_datetime
    # TODO: Explicitly populate these via a query or something
    field :accepted_by, {:array, :string}

    belongs_to :declined_by, User, source: :declinedById, foreign_key: :declinedById
    has_many :emails, Email
    has_many :participants, TradeParticipant
    has_many :recipients, TradeParticipant, where: [participant_type: :recipient]
    has_one :creator, TradeParticipant, where: [participant_type: :creator]
    has_many :traded_items, TradeItem

    many_to_many :traded_players, Player,
      join_through: TradeItem,
      join_keys: [trade_id: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player]

    many_to_many :traded_major_leaguers, Player,
      join_through: TradeItem,
      join_keys: [trade_id: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player],
      where: [league: :major]

    many_to_many :traded_minor_leaguers, Player,
      join_through: TradeItem,
      join_keys: [trade_id: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player],
      where: [league: :minor]

    many_to_many :traded_picks, DraftPick,
      join_through: TradeItem,
      join_keys: [trade_id: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick]

    many_to_many :traded_major_picks, DraftPick,
      join_through: TradeItem,
      join_keys: [trade_id: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :majors]

    many_to_many :traded_minor_picks, DraftPick,
      join_through: TradeItem,
      join_keys: [trade_id: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: {:in, [:high, :low]}]

    many_to_many :traded_high_minor_picks, DraftPick,
      join_through: TradeItem,
      join_keys: [trade_id: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :high]

    many_to_many :traded_low_minor_picks, DraftPick,
      join_through: TradeItem,
      join_keys: [
        trade_id: :id,
        trade_item_id: :id
      ],
      join_where: [
        trade_item_type: :pick
      ],
      where: [
        type: :low
      ]

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [:status, :declined_reason, :accepted_on_date, :accepted_by])
    |> cast_assoc(:creator)
    |> cast_assoc(:recipients)
    |> cast_assoc(:traded_item_players)
    |> cast_assoc(:traded_item_picks)
  end

  def new(params \\ %{}) do
    %__MODULE__{}
    |> changeset(params)
  end
end
