defmodule TradeMachine.ESPN.ConstantsTest do
  use ExUnit.Case, async: true

  alias TradeMachine.ESPN.Constants

  describe "mlb_team_abbrev/1" do
    test "returns uppercased abbreviation for known team" do
      assert Constants.mlb_team_abbrev(1) == "BAL"
      assert Constants.mlb_team_abbrev(10) == "NYY"
      assert Constants.mlb_team_abbrev(19) == "LAD"
      assert Constants.mlb_team_abbrev(30) == "TB"
    end

    test "returns nil for free agents (id 0)" do
      assert Constants.mlb_team_abbrev(0) == nil
    end

    test "returns nil for unknown id" do
      assert Constants.mlb_team_abbrev(999) == nil
    end

    test "returns nil for non-integer input" do
      assert Constants.mlb_team_abbrev(nil) == nil
      assert Constants.mlb_team_abbrev("10") == nil
    end
  end

  describe "pro_team/1" do
    test "returns full team map for known id" do
      assert %{abbrev: "NYY", location: "New York", name: "Yankees"} = Constants.pro_team(10)
    end

    test "returns nil for unknown id" do
      assert Constants.pro_team(999) == nil
    end

    test "returns nil for non-integer input" do
      assert Constants.pro_team(nil) == nil
      assert Constants.pro_team("10") == nil
    end
  end

  describe "position/1" do
    test "returns position string for known ids" do
      assert Constants.position(1) == "SP"
      assert Constants.position(2) == "C"
      assert Constants.position(6) == "SS"
      assert Constants.position(11) == "RP"
    end

    test "returns nil for unknown ids" do
      assert Constants.position(0) == nil
      assert Constants.position(99) == nil
    end

    test "returns nil for non-integer input" do
      assert Constants.position(nil) == nil
    end
  end

  describe "eligible_positions/1" do
    test "filters out non-positional slots and returns comma-separated string" do
      assert Constants.eligible_positions([14, 13, 16, 17]) == "SP"
      assert Constants.eligible_positions([0, 12, 16]) == "C"
    end

    test "returns nil for empty result after filtering" do
      assert Constants.eligible_positions([16, 17]) == nil
    end

    test "returns nil for non-list input" do
      assert Constants.eligible_positions(nil) == nil
    end

    test "handles multiple valid positions" do
      result = Constants.eligible_positions([1, 2, 3, 4])
      assert result == "1B, 2B, 3B, SS"
    end
  end
end
