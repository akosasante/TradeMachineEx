defmodule TradeMachine.ESPN.TypesTest do
  use ExUnit.Case, async: true

  alias TradeMachine.ESPN.Types.{
    LeagueMember,
    RecordStats,
    TeamRecord,
    TransactionCounter,
    FantasyTeam,
    PlayerOwnership,
    PlayerInfo,
    PlayerPoolEntry,
    RosterEntry,
    Roster,
    CumulativeScore,
    MatchupScore,
    ScheduleMatchup
  }

  describe "LeagueMember.from_api/1" do
    test "parses all fields from ESPN API response" do
      data = %{
        "id" => "owner123",
        "displayName" => "John Doe",
        "firstName" => "John",
        "lastName" => "Doe",
        "isLeagueCreator" => true,
        "isLeagueManager" => false
      }

      result = LeagueMember.from_api(data)

      assert result.id == "owner123"
      assert result.display_name == "John Doe"
      assert result.first_name == "John"
      assert result.last_name == "Doe"
      assert result.is_league_creator == true
      assert result.is_league_manager == false
    end

    test "defaults boolean fields to false when missing" do
      result = LeagueMember.from_api(%{"id" => "x", "displayName" => "Test"})

      assert result.is_league_creator == false
      assert result.is_league_manager == false
    end

    test "handles empty map" do
      result = LeagueMember.from_api(%{})

      assert result.id == nil
      assert result.display_name == nil
      assert result.is_league_creator == false
      assert result.is_league_manager == false
    end
  end

  describe "RecordStats.from_api/1" do
    test "returns nil for nil input" do
      assert RecordStats.from_api(nil) == nil
    end

    test "parses all stats fields" do
      data = %{
        "gamesBack" => 2.5,
        "losses" => 10,
        "percentage" => 0.6,
        "pointsAgainst" => 100.5,
        "pointsFor" => 150.0,
        "streakLength" => 3,
        "streakType" => "WIN",
        "ties" => 1,
        "wins" => 15
      }

      result = RecordStats.from_api(data)

      assert result.games_back == 2.5
      assert result.losses == 10
      assert result.percentage == 0.6
      assert result.points_against == 100.5
      assert result.points_for == 150.0
      assert result.streak_length == 3
      assert result.streak_type == "WIN"
      assert result.ties == 1
      assert result.wins == 15
    end

    test "handles missing fields gracefully" do
      result = RecordStats.from_api(%{"wins" => 5})

      assert result.wins == 5
      assert result.losses == nil
    end
  end

  describe "TeamRecord.from_api/1" do
    test "returns nil for nil input" do
      assert TeamRecord.from_api(nil) == nil
    end

    test "parses nested record stats" do
      data = %{
        "away" => %{"wins" => 5, "losses" => 3},
        "division" => %{"wins" => 2, "losses" => 1},
        "home" => %{"wins" => 8, "losses" => 2},
        "overall" => %{"wins" => 13, "losses" => 5}
      }

      result = TeamRecord.from_api(data)

      assert result.away.wins == 5
      assert result.home.wins == 8
      assert result.overall.losses == 5
      assert result.division.wins == 2
    end

    test "handles nil nested records" do
      result = TeamRecord.from_api(%{})

      assert result.away == nil
      assert result.home == nil
    end
  end

  describe "TransactionCounter.from_api/1" do
    test "returns nil for nil input" do
      assert TransactionCounter.from_api(nil) == nil
    end

    test "parses transaction counter fields" do
      data = %{
        "acquisitionBudgetSpent" => 50,
        "acquisitions" => 12,
        "drops" => 8,
        "matchupAcquisitionTotals" => %{"1" => 2},
        "misc" => 0,
        "moveToActive" => 3,
        "moveToIR" => 2,
        "paid" => 10.0,
        "teamCharges" => 5.0,
        "trades" => 4
      }

      result = TransactionCounter.from_api(data)

      assert result.acquisitions == 12
      assert result.drops == 8
      assert result.trades == 4
      assert result.move_to_ir == 2
      assert result.matchup_acquisition_totals == %{"1" => 2}
    end
  end

  describe "FantasyTeam.from_api/1" do
    test "parses all team fields including nested records" do
      data = %{
        "id" => 1,
        "abbrev" => "TEAM",
        "name" => "My Team",
        "location" => "New York",
        "nickname" => "Sluggers",
        "owners" => ["owner1", "owner2"],
        "primaryOwner" => "owner1",
        "logo" => "https://example.com/logo.png",
        "logoType" => "CUSTOM",
        "points" => 1500.5,
        "waiverRank" => 3,
        "valuesByStat" => %{"0" => 100},
        "record" => %{"overall" => %{"wins" => 10, "losses" => 5}},
        "transactionCounter" => %{"trades" => 3}
      }

      result = FantasyTeam.from_api(data)

      assert result.id == 1
      assert result.abbrev == "TEAM"
      assert result.name == "My Team"
      assert result.owners == ["owner1", "owner2"]
      assert result.primary_owner == "owner1"
      assert result.waiver_rank == 3
      assert result.record.overall.wins == 10
      assert result.transaction_counter.trades == 3
    end

    test "handles minimal data" do
      result = FantasyTeam.from_api(%{"id" => 5})

      assert result.id == 5
      assert result.name == nil
      assert result.record == nil
      assert result.transaction_counter == nil
    end
  end

  describe "PlayerOwnership.from_api/1" do
    test "returns nil for nil input" do
      assert PlayerOwnership.from_api(nil) == nil
    end

    test "parses ownership percentages" do
      data = %{
        "percentOwned" => 85.5,
        "percentStarted" => 60.2,
        "percentChange" => 3.1
      }

      result = PlayerOwnership.from_api(data)

      assert result.percent_owned == 85.5
      assert result.percent_started == 60.2
      assert result.percent_change == 3.1
    end
  end

  describe "PlayerInfo.from_api/1" do
    test "parses all player info fields" do
      data = %{
        "id" => 12_345,
        "firstName" => "Mike",
        "lastName" => "Trout",
        "fullName" => "Mike Trout",
        "proTeamId" => 3,
        "eligibleSlots" => [5, 12, 16],
        "defaultPositionId" => 8,
        "jersey" => "27",
        "injured" => false,
        "injuryStatus" => "ACTIVE",
        "active" => true,
        "ownership" => %{"percentOwned" => 99.9}
      }

      result = PlayerInfo.from_api(data)

      assert result.id == 12_345
      assert result.full_name == "Mike Trout"
      assert result.pro_team_id == 3
      assert result.eligible_slots == [5, 12, 16]
      assert result.jersey == "27"
      assert result.injured == false
      assert result.active == true
      assert result.ownership.percent_owned == 99.9
    end

    test "handles missing ownership" do
      result = PlayerInfo.from_api(%{"id" => 1})

      assert result.id == 1
      assert result.ownership == nil
    end
  end

  describe "PlayerPoolEntry.from_api/1" do
    test "parses pool entry with nested player" do
      data = %{
        "id" => 100,
        "onTeamId" => 5,
        "status" => "ONTEAM",
        "player" => %{
          "id" => 12_345,
          "fullName" => "Mike Trout"
        }
      }

      result = PlayerPoolEntry.from_api(data)

      assert result.id == 100
      assert result.on_team_id == 5
      assert result.status == "ONTEAM"
      assert result.player.id == 12_345
      assert result.player.full_name == "Mike Trout"
    end

    test "handles missing player with empty map fallback" do
      result = PlayerPoolEntry.from_api(%{"id" => 1})

      assert result.id == 1
      assert result.player != nil
      assert result.player.id == nil
    end
  end

  describe "RosterEntry.from_api/1" do
    test "parses roster entry with nested pool entry" do
      data = %{
        "lineupSlotId" => 0,
        "playerId" => 12_345,
        "playerPoolEntry" => %{
          "id" => 12_345,
          "onTeamId" => 1,
          "status" => "ONTEAM",
          "player" => %{"id" => 12_345, "fullName" => "Test Player"}
        }
      }

      result = RosterEntry.from_api(data)

      assert result.lineup_slot_id == 0
      assert result.player_id == 12_345
      assert result.player_pool_entry.on_team_id == 1
    end

    test "handles missing player pool entry with empty map fallback" do
      result = RosterEntry.from_api(%{"playerId" => 1})

      assert result.player_pool_entry != nil
    end
  end

  describe "Roster.from_api/1" do
    test "parses roster with multiple entries" do
      data = %{
        "entries" => [
          %{
            "lineupSlotId" => 0,
            "playerId" => 1,
            "playerPoolEntry" => %{"id" => 1, "player" => %{"id" => 1}}
          },
          %{
            "lineupSlotId" => 1,
            "playerId" => 2,
            "playerPoolEntry" => %{"id" => 2, "player" => %{"id" => 2}}
          }
        ]
      }

      result = Roster.from_api(data)

      assert length(result.entries) == 2
      assert Enum.at(result.entries, 0).player_id == 1
      assert Enum.at(result.entries, 1).player_id == 2
    end

    test "handles missing entries with empty list" do
      result = Roster.from_api(%{})

      assert result.entries == []
    end
  end

  describe "CumulativeScore.from_api/1" do
    test "returns nil for nil input" do
      assert CumulativeScore.from_api(nil) == nil
    end

    test "parses score fields" do
      data = %{
        "losses" => 3,
        "wins" => 7,
        "ties" => 0,
        "scoreByStat" => %{"0" => 125.5}
      }

      result = CumulativeScore.from_api(data)

      assert result.wins == 7
      assert result.losses == 3
      assert result.ties == 0
      assert result.score_by_stat == %{"0" => 125.5}
    end
  end

  describe "MatchupScore.from_api/1" do
    test "returns nil for nil input" do
      assert MatchupScore.from_api(nil) == nil
    end

    test "parses matchup score with nested structs" do
      data = %{
        "teamId" => 1,
        "totalPoints" => 150.5,
        "totalPointsLive" => 148.0,
        "cumulativeScore" => %{"wins" => 5, "losses" => 2},
        "rosterForMatchupPeriod" => %{
          "entries" => [
            %{
              "playerId" => 1,
              "lineupSlotId" => 0,
              "playerPoolEntry" => %{"id" => 1, "player" => %{"id" => 1}}
            }
          ]
        }
      }

      result = MatchupScore.from_api(data)

      assert result.team_id == 1
      assert result.total_points == 150.5
      assert result.cumulative_score.wins == 5
      assert length(result.roster_for_matchup_period.entries) == 1
    end

    test "handles missing roster with empty map fallback" do
      result = MatchupScore.from_api(%{"teamId" => 1})

      assert result.roster_for_matchup_period.entries == []
    end
  end

  describe "ScheduleMatchup.from_api/1" do
    test "parses matchup with home and away scores" do
      data = %{
        "id" => 42,
        "winner" => "HOME",
        "home" => %{"teamId" => 1, "totalPoints" => 150.0},
        "away" => %{"teamId" => 2, "totalPoints" => 120.0}
      }

      result = ScheduleMatchup.from_api(data)

      assert result.id == 42
      assert result.winner == "HOME"
      assert result.home.team_id == 1
      assert result.away.team_id == 2
    end

    test "handles nil home/away" do
      result = ScheduleMatchup.from_api(%{"id" => 1})

      assert result.home == nil
      assert result.away == nil
    end
  end
end
