defmodule TradeMachine.Discord.FormatterTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.Formatter

  describe "format_item/1 with major players" do
    test "formats player with all info" do
      item = %{type: :major_player, name: "Ketel Marte", mlb_team: "ARI", position: "2B"}
      assert Formatter.format_item(item) == "• **Ketel Marte** (Majors - ARI - 2B)"
    end

    test "skips missing mlb_team" do
      item = %{type: :major_player, name: "Ketel Marte", mlb_team: nil, position: "2B"}
      assert Formatter.format_item(item) == "• **Ketel Marte** (Majors - 2B)"
    end

    test "skips missing position" do
      item = %{type: :major_player, name: "Ketel Marte", mlb_team: "ARI", position: nil}
      assert Formatter.format_item(item) == "• **Ketel Marte** (Majors - ARI)"
    end

    test "shows only Majors when both mlb_team and position are missing" do
      item = %{type: :major_player, name: "Ketel Marte", mlb_team: nil, position: nil}
      assert Formatter.format_item(item) == "• **Ketel Marte** (Majors)"
    end
  end

  describe "format_item/1 with minor players" do
    test "formats player with all info" do
      item = %{
        type: :minor_player,
        name: "Patrick Forbes",
        level: :high,
        mlb_team: "SEA",
        position: "OF"
      }

      assert Formatter.format_item(item) == "• **Patrick Forbes** (High Minors - SEA - OF)"
    end

    test "formats low minors correctly" do
      item = %{
        type: :minor_player,
        name: "Patrick Forbes",
        level: :low,
        mlb_team: nil,
        position: nil
      }

      assert Formatter.format_item(item) == "• **Patrick Forbes** (Low Minors)"
    end

    test "shows Minors when level is nil" do
      item = %{
        type: :minor_player,
        name: "Patrick Forbes",
        level: nil,
        mlb_team: nil,
        position: nil
      }

      assert Formatter.format_item(item) == "• **Patrick Forbes** (Minors)"
    end

    test "skips missing mlb_team but keeps level and position" do
      item = %{
        type: :minor_player,
        name: "Patrick Forbes",
        level: :high,
        mlb_team: nil,
        position: "SS"
      }

      assert Formatter.format_item(item) == "• **Patrick Forbes** (High Minors - SS)"
    end
  end

  describe "format_item/1 with draft picks" do
    test "formats major league pick" do
      item = %{type: :pick, owner_name: "Ryan", round: 2, pick_type: :majors, season: 2026}
      assert Formatter.format_item(item) == "• **Ryan's** 2nd round Major League pick"
    end

    test "formats high minors pick" do
      item = %{type: :pick, owner_name: "Mikey", round: 3, pick_type: :high, season: 2026}
      assert Formatter.format_item(item) == "• **Mikey's** 3rd round High Minors pick"
    end

    test "formats low minors pick" do
      item = %{type: :pick, owner_name: "James", round: 1, pick_type: :low, season: 2026}
      assert Formatter.format_item(item) == "• **James's** 1st round Low Minors pick"
    end

    test "handles Decimal round numbers" do
      item = %{
        type: :pick,
        owner_name: "Ryan",
        round: Decimal.new(4),
        pick_type: :majors,
        season: 2027
      }

      assert Formatter.format_item(item) == "• **Ryan's** 4th round Major League pick"
    end
  end

  describe "format_items/1" do
    test "returns no items text for empty list" do
      assert Formatter.format_items([]) == "_No items_"
    end

    test "joins multiple items with newlines" do
      items = [
        %{type: :major_player, name: "Ketel Marte", mlb_team: "ARI", position: "2B"},
        %{type: :pick, owner_name: "Mikey", round: 2, pick_type: :majors, season: 2026}
      ]

      result = Formatter.format_items(items)
      lines = String.split(result, "\n")
      assert length(lines) == 2
      assert Enum.at(lines, 0) =~ "Ketel Marte"
      assert Enum.at(lines, 1) =~ "Mikey"
    end
  end

  describe "format_participant_name/2" do
    test "uses csv_name when available" do
      owners = [%{csv_name: "Ryan", display_name: "Ryan Neeson"}]
      assert Formatter.format_participant_name(owners, "The Mad King") == "Ryan"
    end

    test "falls back to team name when csv_name is nil" do
      owners = [%{csv_name: nil, display_name: "Ryan Neeson"}]
      assert Formatter.format_participant_name(owners, "The Mad King") == "The Mad King"
    end

    test "uses first available csv_name from multiple owners" do
      owners = [
        %{csv_name: nil, display_name: "James"},
        %{csv_name: "James", display_name: "James Smith"}
      ]

      assert Formatter.format_participant_name(owners, "Team James") == "James"
    end

    test "falls back to team name when no owners have csv_name" do
      owners = [
        %{csv_name: nil, display_name: "James"},
        %{csv_name: nil, display_name: "Sarah"}
      ]

      assert Formatter.format_participant_name(owners, "Team James") == "Team James"
    end
  end

  describe "format_mentions/1" do
    test "formats Discord mentions when discord_user_id is available" do
      owners = [%{discord_user_id: "667047645914857503", display_name: "Ryan"}]
      assert Formatter.format_mentions(owners) == "<@667047645914857503>"
    end

    test "formats multiple Discord mentions" do
      owners = [
        %{discord_user_id: "111", display_name: "Ryan"},
        %{discord_user_id: "222", display_name: "Mikey"}
      ]

      assert Formatter.format_mentions(owners) == "<@111>, <@222>"
    end

    test "falls back to @display_name when no discord_user_id" do
      owners = [%{discord_user_id: nil, display_name: "James"}]
      assert Formatter.format_mentions(owners) == "@James"
    end

    test "only mentions owners with discord_user_id" do
      owners = [
        %{discord_user_id: "111", display_name: "Ryan"},
        %{discord_user_id: nil, display_name: "James"}
      ]

      assert Formatter.format_mentions(owners) == "<@111>"
    end
  end

  describe "format_ordinal/1" do
    test "formats 1st" do
      assert Formatter.format_ordinal(1) == "1st"
    end

    test "formats 2nd" do
      assert Formatter.format_ordinal(2) == "2nd"
    end

    test "formats 3rd" do
      assert Formatter.format_ordinal(3) == "3rd"
    end

    test "formats 4th and above" do
      assert Formatter.format_ordinal(4) == "4th"
      assert Formatter.format_ordinal(10) == "10th"
    end

    test "handles Decimal input" do
      assert Formatter.format_ordinal(Decimal.new(1)) == "1st"
      assert Formatter.format_ordinal(Decimal.new(5)) == "5th"
    end
  end

  describe "format_pick_league/1" do
    test "formats major league" do
      assert Formatter.format_pick_league(:majors) == "Major League"
    end

    test "formats high minors" do
      assert Formatter.format_pick_league(:high) == "High Minors"
    end

    test "formats low minors" do
      assert Formatter.format_pick_league(:low) == "Low Minors"
    end
  end

  describe "format_minor_level/1" do
    test "formats high minors" do
      assert Formatter.format_minor_level(:high) == "High Minors"
    end

    test "formats low minors" do
      assert Formatter.format_minor_level(:low) == "Low Minors"
    end

    test "defaults to Minors for nil" do
      assert Formatter.format_minor_level(nil) == "Minors"
    end
  end
end
