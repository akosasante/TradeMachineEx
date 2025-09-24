defmodule TradeMachine.Data.Team do
  use TradeMachine.Schema

  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Trade
  alias TradeMachine.Data.TradeItem
  alias TradeMachine.Data.TradeParticipant
  alias TradeMachine.Data.User

  typed_schema "team" do
    field :name, :string, null: false
    field :espn_id, :integer
    field(:status, Ecto.Enum, values: [active: "1", disabled: "2"], null: false)
    field :espn_team, :map, load_in_query: false

    has_many :owned_picks, DraftPick, foreign_key: :currentOwnerId

    has_many :owned_players, Player, foreign_key: :leagueTeamId
    has_many :original_picks, DraftPick, foreign_key: :originalOwnerId

    has_many :current_owners, User, foreign_key: :teamId

    many_to_many :trades_involved_in, Trade,
      join_through: TradeParticipant,
      join_keys: [team_id: :id, trade_id: :id]

    many_to_many :trades_sent, Trade,
      join_through: TradeParticipant,
      join_keys: [team_id: :id, trade_id: :id],
      join_where: [participant_type: :creator]

    many_to_many :trades_received, Trade,
      join_through: TradeParticipant,
      join_keys: [team_id: :id, trade_id: :id],
      join_where: [participant_type: :recipient]

    has_many :trade_items_sent, TradeItem, foreign_key: :senderId
    has_many :trade_items_received, TradeItem, foreign_key: :recipientId

    many_to_many :players_sent, Player,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player]

    many_to_many :major_leaguers_sent, Player,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player],
      where: [league: :major]

    many_to_many :minor_leaguers_sent, Player,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player],
      where: [league: :minor]

    many_to_many :picks_sent, DraftPick,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick]

    many_to_many :major_picks_sent, DraftPick,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :majors]

    many_to_many :high_minors_picks_sent, DraftPick,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :high]

    many_to_many :low_minors_picks_sent, DraftPick,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :low]

    many_to_many :minors_picks_sent, DraftPick,
      join_through: TradeItem,
      join_keys: [senderId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: {:in, [:high, :low]}]

    many_to_many :players_received, Player,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player]

    many_to_many :major_leaguers_received, Player,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player],
      where: [league: :major]

    many_to_many :minor_leaguers_received, Player,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :player],
      where: [league: :minor]

    many_to_many :picks_received, DraftPick,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick]

    many_to_many :major_picks_received, DraftPick,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :majors]

    many_to_many :high_minors_picks_received, DraftPick,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :high]

    many_to_many :low_minors_picks_received, DraftPick,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: :low]

    many_to_many :minors_picks_received, DraftPick,
      join_through: TradeItem,
      join_keys: [recipientId: :id, trade_item_id: :id],
      join_where: [trade_item_type: :pick],
      where: [type: {:in, [:high, :low]}]

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, [])
  end
end
