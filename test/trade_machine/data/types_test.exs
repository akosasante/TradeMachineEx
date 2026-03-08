defmodule TradeMachine.Data.TypesTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Data.Types.{EligiblePositions, TradedMajor, TradedMinor, TradedPick}

  describe "EligiblePositions" do
    test "type/0 returns array of integers" do
      assert EligiblePositions.type() == {:array, :integer}
    end

    test "cast/1 converts string positions to integer IDs" do
      assert {:ok, [0, 12, 16]} = EligiblePositions.cast(["C", "UTIL", "BE"])
    end

    test "cast/1 returns :unknown_position for unrecognized strings" do
      assert {:ok, [:unknown_position]} = EligiblePositions.cast(["FAKE"])
    end

    test "cast/1 returns error for non-list" do
      assert :error = EligiblePositions.cast("C")
      assert :error = EligiblePositions.cast(42)
    end

    test "load/1 converts integer IDs to string positions" do
      assert {:ok, ["C", "UTIL", "BE"]} = EligiblePositions.load([0, 12, 16])
    end

    test "load/1 filters out unknown integer IDs" do
      assert {:ok, ["SP"]} = EligiblePositions.load([14, 999])
    end

    test "load/1 handles nil" do
      assert {:ok, nil} = EligiblePositions.load(nil)
    end

    test "load/1 handles single integer" do
      assert {:ok, "C"} = EligiblePositions.load(0)
    end

    test "dump/1 passes through integer lists" do
      assert {:ok, [0, 14]} = EligiblePositions.dump([0, 14])
    end

    test "dump/1 returns error for non-integer lists" do
      assert :error = EligiblePositions.dump(["C", "SP"])
    end

    test "dump/1 returns error for non-list" do
      assert :error = EligiblePositions.dump("C")
    end

    test "cast then dump round-trip preserves data" do
      {:ok, cast_result} = EligiblePositions.cast(["SP", "RP", "P"])
      {:ok, dumped} = EligiblePositions.dump(cast_result)
      {:ok, loaded} = EligiblePositions.load(dumped)
      assert loaded == ["SP", "RP", "P"]
    end
  end

  describe "TradedMajor" do
    test "type/0 returns :map" do
      assert TradedMajor.type() == :map
    end

    test "cast/1 converts atom-keyed maps to string-keyed maps" do
      input = [
        %{
          id: "player-1",
          name: "Mike Trout",
          league: "AL",
          main_position: "CF",
          mlb_team: "LAA",
          owned_by: "team-1",
          recipient: "team-2",
          sender: "team-1",
          trade_id: "trade-1",
          eligible_positions: ["CF", "OF", "UTIL"]
        }
      ]

      {:ok, [result]} = TradedMajor.cast(input)

      assert result["name"] == "Mike Trout"
      assert result["id"] == "player-1"
      assert result["mainPosition"] == "CF"
      assert result["mlbTeam"] == "LAA"
      assert result["ownerTeam"] == "team-1"
      assert result["tradeId"] == "trade-1"
      assert is_list(result["eligiblePositions"])
    end

    test "cast/1 handles a single map" do
      input = %{id: "p1", name: "Test", eligible_positions: ["SP"]}
      {:ok, result} = TradedMajor.cast(input)
      assert result["id"] == "p1"
    end

    test "cast/1 returns error for invalid input" do
      assert :error = TradedMajor.cast("invalid")
      assert :error = TradedMajor.cast(42)
    end

    test "load/1 converts string-keyed maps to atom-keyed maps" do
      input = [
        %{
          "id" => "player-1",
          "name" => "Mike Trout",
          "league" => "AL",
          "mainPosition" => "CF",
          "mlbTeam" => "LAA",
          "ownerTeam" => "team-1",
          "recipient" => "team-2",
          "sender" => "team-1",
          "tradeId" => "trade-1",
          "eligiblePositions" => [5, 12]
        }
      ]

      {:ok, [result]} = TradedMajor.load(input)

      assert result.name == "Mike Trout"
      assert result.main_position == "CF"
      assert result.mlb_team == "LAA"
      assert result.owned_by == "team-1"
      assert result.trade_id == "trade-1"
      assert is_list(result.eligible_positions)
    end

    test "dump/1 passes through string-keyed lists" do
      input = [{"name", "Test"}, {"id", "1"}]
      assert {:ok, ^input} = TradedMajor.dump(input)
    end

    test "dump/1 returns error for non-string-keyed lists" do
      assert :error = TradedMajor.dump([{:name, "Test"}])
    end

    test "dump/1 returns error for non-list" do
      assert :error = TradedMajor.dump("invalid")
      assert :error = TradedMajor.dump(42)
    end
  end

  describe "TradedMinor" do
    test "type/0 returns :map" do
      assert TradedMinor.type() == :map
    end

    test "cast/1 converts atom-keyed maps to string-keyed maps" do
      input = [
        %{
          id: "minor-1",
          name: "Prospect A",
          league: "Low-A",
          minor_league_level: "A",
          minor_team: "Dunedin",
          owned_by: "team-1",
          position: "SS",
          recipient: "team-2",
          sender: "team-1",
          trade_id: "trade-1"
        }
      ]

      {:ok, [result]} = TradedMinor.cast(input)

      assert result["name"] == "Prospect A"
      assert result["minorLeagueLevel"] == "A"
      assert result["minorTeam"] == "Dunedin"
      assert result["position"] == "SS"
      assert result["ownerTeam"] == "team-1"
      assert result["tradeId"] == "trade-1"
    end

    test "cast/1 returns error for invalid input" do
      assert :error = TradedMinor.cast("invalid")
    end

    test "load/1 converts string-keyed maps to atom-keyed maps" do
      input = [
        %{
          "id" => "minor-1",
          "name" => "Prospect A",
          "minorLeagueLevel" => "A",
          "minorTeam" => "Dunedin",
          "ownerTeam" => "team-1",
          "position" => "SS",
          "recipient" => "team-2",
          "sender" => "team-1",
          "tradeId" => "trade-1"
        }
      ]

      {:ok, [result]} = TradedMinor.load(input)

      assert result.name == "Prospect A"
      assert result.minor_league_level == "A"
      assert result.minor_team == "Dunedin"
      assert result.owned_by == "team-1"
      assert result.trade_id == "trade-1"
    end

    test "dump/1 passes through string-keyed lists" do
      input = [{"name", "Test"}]
      assert {:ok, ^input} = TradedMinor.dump(input)
    end

    test "dump/1 returns error for non-list" do
      assert :error = TradedMinor.dump("invalid")
    end
  end

  describe "TradedPick" do
    test "type/0 returns :map" do
      assert TradedPick.type() == :map
    end

    test "cast/1 converts atom-keyed maps to string-keyed maps" do
      input = [
        %{
          id: "pick-1",
          owned_by: "team-1",
          original_owner: "team-2",
          pick_number: 5,
          round: 1,
          season: 2026,
          type: "MLBD",
          recipient: "team-1",
          sender: "team-2",
          trade_id: "trade-1"
        }
      ]

      {:ok, [result]} = TradedPick.cast(input)

      assert result["id"] == "pick-1"
      assert result["currentPickHolder"] == "team-1"
      assert result["originalPickOwner"] == "team-2"
      assert result["pickNumber"] == 5
      assert result["round"] == 1
      assert result["season"] == 2026
      assert result["type"] == "MLBD"
      assert result["tradeId"] == "trade-1"
    end

    test "cast/1 returns error for invalid input" do
      assert :error = TradedPick.cast("invalid")
    end

    test "load/1 converts string-keyed maps to atom-keyed maps" do
      input = [
        %{
          "id" => "pick-1",
          "currentPickHolder" => "team-1",
          "originalPickOwner" => "team-2",
          "pickNumber" => 5,
          "round" => 1,
          "season" => 2026,
          "type" => "MLBD",
          "recipient" => "team-1",
          "sender" => "team-2",
          "tradeId" => "trade-1"
        }
      ]

      {:ok, [result]} = TradedPick.load(input)

      assert result.id == "pick-1"
      assert result.owned_by == "team-1"
      assert result.original_owner == "team-2"
      assert result.pick_number == 5
      assert result.round == 1
      assert result.season == 2026
      assert result.trade_id == "trade-1"
    end

    test "dump/1 passes through string-keyed lists" do
      input = [{"id", "pick-1"}]
      assert {:ok, ^input} = TradedPick.dump(input)
    end

    test "dump/1 returns error for non-list" do
      assert :error = TradedPick.dump("invalid")
    end
  end
end
