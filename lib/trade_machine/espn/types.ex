defmodule TradeMachine.ESPN.Types do
  @moduledoc """
  Ecto embedded schemas for ESPN Fantasy API responses.
  
  These schemas provide type-safe structs for parsing and working with ESPN API data.
  """

  defmodule LeagueMember do
    @moduledoc "ESPN league member information"
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :id, :string
      field :display_name, :string
      field :first_name, :string
      field :last_name, :string
      field :is_league_creator, :boolean
      field :is_league_manager, :boolean
    end

    def changeset(member, attrs) do
      member
      |> cast(attrs, [:id, :display_name, :first_name, :last_name, :is_league_creator, :is_league_manager])
      |> validate_required([:id, :display_name])
    end

    @doc "Parse ESPN API response into LeagueMember struct"
    def from_api(data) do
      %__MODULE__{
        id: data["id"],
        display_name: data["displayName"],
        first_name: data["firstName"],
        last_name: data["lastName"],
        is_league_creator: data["isLeagueCreator"] || false,
        is_league_manager: data["isLeagueManager"] || false
      }
    end
  end

  defmodule RecordStats do
    @moduledoc "Team record statistics"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :games_back, :float
      field :losses, :integer
      field :percentage, :float
      field :points_against, :float
      field :points_for, :float
      field :streak_length, :integer
      field :streak_type, :string
      field :ties, :integer
      field :wins, :integer
    end

    def from_api(nil), do: nil

    def from_api(data) do
      %__MODULE__{
        games_back: data["gamesBack"],
        losses: data["losses"],
        percentage: data["percentage"],
        points_against: data["pointsAgainst"],
        points_for: data["pointsFor"],
        streak_length: data["streakLength"],
        streak_type: data["streakType"],
        ties: data["ties"],
        wins: data["wins"]
      }
    end
  end

  defmodule TeamRecord do
    @moduledoc "Team record across different contexts"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      embeds_one :away, RecordStats
      embeds_one :division, RecordStats
      embeds_one :home, RecordStats
      embeds_one :overall, RecordStats
    end

    def from_api(nil), do: nil

    def from_api(data) do
      %__MODULE__{
        away: RecordStats.from_api(data["away"]),
        division: RecordStats.from_api(data["division"]),
        home: RecordStats.from_api(data["home"]),
        overall: RecordStats.from_api(data["overall"])
      }
    end
  end

  defmodule TransactionCounter do
    @moduledoc "Team transaction statistics"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :acquisition_budget_spent, :integer
      field :acquisitions, :integer
      field :drops, :integer
      field :matchup_acquisition_totals, :map
      field :misc, :integer
      field :move_to_active, :integer
      field :move_to_ir, :integer
      field :paid, :float
      field :team_charges, :float
      field :trades, :integer
    end

    def from_api(nil), do: nil

    def from_api(data) do
      %__MODULE__{
        acquisition_budget_spent: data["acquisitionBudgetSpent"],
        acquisitions: data["acquisitions"],
        drops: data["drops"],
        matchup_acquisition_totals: data["matchupAcquisitionTotals"],
        misc: data["misc"],
        move_to_active: data["moveToActive"],
        move_to_ir: data["moveToIR"],
        paid: data["paid"],
        team_charges: data["teamCharges"],
        trades: data["trades"]
      }
    end
  end

  defmodule FantasyTeam do
    @moduledoc "ESPN fantasy team"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :id, :integer
      field :abbrev, :string
      field :name, :string
      field :location, :string
      field :nickname, :string
      field :owners, {:array, :string}
      field :primary_owner, :string
      field :logo, :string
      field :logo_type, :string
      field :points, :float
      field :waiver_rank, :integer
      field :values_by_stat, :map

      embeds_one :record, TeamRecord
      embeds_one :transaction_counter, TransactionCounter
    end

    def from_api(data) do
      %__MODULE__{
        id: data["id"],
        abbrev: data["abbrev"],
        name: data["name"],
        location: data["location"],
        nickname: data["nickname"],
        owners: data["owners"],
        primary_owner: data["primaryOwner"],
        logo: data["logo"],
        logo_type: data["logoType"],
        points: data["points"],
        waiver_rank: data["waiverRank"],
        values_by_stat: data["valuesByStat"],
        record: TeamRecord.from_api(data["record"]),
        transaction_counter: TransactionCounter.from_api(data["transactionCounter"])
      }
    end
  end

  defmodule PlayerOwnership do
    @moduledoc "Player ownership statistics"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :percent_owned, :float
      field :percent_started, :float
      field :percent_change, :float
    end

    def from_api(nil), do: nil

    def from_api(data) do
      %__MODULE__{
        percent_owned: data["percentOwned"],
        percent_started: data["percentStarted"],
        percent_change: data["percentChange"]
      }
    end
  end

  defmodule PlayerInfo do
    @moduledoc "MLB player information"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :id, :integer
      field :first_name, :string
      field :last_name, :string
      field :full_name, :string
      field :pro_team_id, :integer
      field :eligible_slots, {:array, :integer}
      field :default_position_id, :integer
      field :jersey, :string
      field :injured, :boolean
      field :injury_status, :string
      field :active, :boolean

      embeds_one :ownership, PlayerOwnership
    end

    def from_api(data) do
      %__MODULE__{
        id: data["id"],
        first_name: data["firstName"],
        last_name: data["lastName"],
        full_name: data["fullName"],
        pro_team_id: data["proTeamId"],
        eligible_slots: data["eligibleSlots"],
        default_position_id: data["defaultPositionId"],
        jersey: data["jersey"],
        injured: data["injured"],
        injury_status: data["injuryStatus"],
        active: data["active"],
        ownership: PlayerOwnership.from_api(data["ownership"])
      }
    end
  end

  defmodule PlayerPoolEntry do
    @moduledoc "Player pool entry (player in league context)"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :id, :integer
      field :on_team_id, :integer
      field :status, :string

      embeds_one :player, PlayerInfo
    end

    def from_api(data) do
      %__MODULE__{
        id: data["id"],
        on_team_id: data["onTeamId"],
        status: data["status"],
        player: PlayerInfo.from_api(data["player"] || %{})
      }
    end
  end

  defmodule RosterEntry do
    @moduledoc "Roster entry for a team"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :lineup_slot_id, :integer
      field :player_id, :integer

      embeds_one :player_pool_entry, PlayerPoolEntry
    end

    def from_api(data) do
      %__MODULE__{
        lineup_slot_id: data["lineupSlotId"],
        player_id: data["playerId"],
        player_pool_entry: PlayerPoolEntry.from_api(data["playerPoolEntry"] || %{})
      }
    end
  end

  defmodule Roster do
    @moduledoc "Team roster"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      embeds_many :entries, RosterEntry
    end

    def from_api(data) do
      entries =
        (data["entries"] || [])
        |> Enum.map(&RosterEntry.from_api/1)

      %__MODULE__{entries: entries}
    end
  end

  defmodule CumulativeScore do
    @moduledoc "Cumulative matchup score"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :losses, :integer
      field :wins, :integer
      field :ties, :integer
      field :score_by_stat, :map
    end

    def from_api(nil), do: nil

    def from_api(data) do
      %__MODULE__{
        losses: data["losses"],
        wins: data["wins"],
        ties: data["ties"],
        score_by_stat: data["scoreByStat"]
      }
    end
  end

  defmodule MatchupScore do
    @moduledoc "Matchup score for home or away team"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :team_id, :integer
      field :total_points, :float
      field :total_points_live, :float

      embeds_one :cumulative_score, CumulativeScore
      embeds_one :roster_for_matchup_period, Roster
    end

    def from_api(nil), do: nil

    def from_api(data) do
      %__MODULE__{
        team_id: data["teamId"],
        total_points: data["totalPoints"],
        total_points_live: data["totalPointsLive"],
        cumulative_score: CumulativeScore.from_api(data["cumulativeScore"]),
        roster_for_matchup_period: Roster.from_api(data["rosterForMatchupPeriod"] || %{})
      }
    end
  end

  defmodule ScheduleMatchup do
    @moduledoc "Schedule matchup between two teams"
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :id, :integer
      field :winner, :string

      embeds_one :home, MatchupScore
      embeds_one :away, MatchupScore
    end

    def from_api(data) do
      %__MODULE__{
        id: data["id"],
        winner: data["winner"],
        home: MatchupScore.from_api(data["home"]),
        away: MatchupScore.from_api(data["away"])
      }
    end
  end
end
