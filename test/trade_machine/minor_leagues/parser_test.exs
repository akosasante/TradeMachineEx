defmodule TradeMachine.MinorLeagues.ParserTest do
  use ExUnit.Case, async: true

  alias TradeMachine.MinorLeagues.Parser

  # Fixture data modeled after the real Google Sheet structure.
  # 5 teams × 9 columns = 45 columns per row.

  @legend_row [
    "",
    "",
    "",
    "# = Player has been assigned to an HM level but has not yet made an appearance",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    ""
  ]

  @separator_row List.duplicate("", 45)

  @header_row [
    "1",
    "0",
    "#N/A",
    "Flex",
    "",
    "",
    "",
    "K",
    "T",
    "1",
    "0",
    "#N/A",
    "Newton",
    "",
    "",
    "",
    "K",
    "T",
    "1",
    "0",
    "#N/A",
    "RKR",
    "",
    "",
    "",
    "K",
    "T",
    "1",
    "0",
    "#N/A",
    "Kaminski",
    "",
    "",
    "",
    "K",
    "T",
    "1",
    "0",
    "#N/A",
    "Ian",
    "",
    "",
    "",
    "",
    "T"
  ]

  @player_row_hm [
    "1",
    "HM",
    "1",
    "Andrew Walters",
    "*",
    "P",
    "CLE",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "5",
    "Bryan Ramos",
    "**",
    "3B",
    "CWS",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "1",
    "Ty Madden",
    "*",
    "P",
    "DET",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "4",
    "Nick Yorke",
    "**",
    "2B",
    "PIT",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "1",
    "Jackson Ferris",
    "",
    "P",
    "LAD",
    "FALSE",
    "FALSE"
  ]

  @player_row_lm [
    "1",
    "LM",
    "1",
    "Brandon Clarke",
    "",
    "P",
    "BOS",
    "FALSE",
    "FALSE",
    "1",
    "LM",
    "3",
    "Luis Merejo",
    "",
    "1B",
    "CLE",
    "FALSE",
    "FALSE",
    "1",
    "LM",
    "1",
    "Braylon Doughty",
    "",
    "P",
    "CLE",
    "FALSE",
    "FALSE",
    "1",
    "LM",
    "5",
    "Myles Naylor",
    "",
    "3B",
    "OAK",
    "FALSE",
    "FALSE",
    "1",
    "LM",
    "1",
    "Anderson Brito",
    "",
    "P",
    "HOU",
    "FALSE",
    "FALSE"
  ]

  @partial_player_row [
    "1",
    "HM",
    "7",
    "Emmanuel Rodriguez",
    "",
    "OF",
    "MIN",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "#N/A",
    "",
    "",
    "",
    "",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "#N/A",
    "",
    "",
    "",
    "",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "7",
    "Braden Montgomery",
    "",
    "OF",
    "CWS",
    "FALSE",
    "FALSE",
    "1",
    "HM",
    "#N/A",
    "",
    "",
    "",
    "",
    "FALSE",
    "FALSE"
  ]

  @second_header_row [
    "2",
    "0",
    "#N/A",
    "TeamSix",
    "",
    "",
    "",
    "K",
    "T",
    "2",
    "0",
    "#N/A",
    "TeamSeven",
    "",
    "",
    "",
    "K",
    "T",
    "2",
    "0",
    "#N/A",
    "TeamEight",
    "",
    "",
    "",
    "K",
    "T",
    "2",
    "0",
    "#N/A",
    "TeamNine",
    "",
    "",
    "",
    "K",
    "T",
    "2",
    "0",
    "#N/A",
    "TeamTen",
    "",
    "",
    "",
    "K",
    "T"
  ]

  @second_player_row [
    "2",
    "HM",
    "1",
    "Player Six",
    "",
    "P",
    "NYY",
    "FALSE",
    "FALSE",
    "2",
    "HM",
    "2",
    "Player Seven",
    "",
    "C",
    "LAD",
    "FALSE",
    "FALSE",
    "2",
    "HM",
    "6",
    "Player Eight",
    "",
    "SS",
    "BOS",
    "FALSE",
    "FALSE",
    "2",
    "HM",
    "3",
    "Player Nine",
    "",
    "1B",
    "CHC",
    "FALSE",
    "FALSE",
    "2",
    "HM",
    "7",
    "Player Ten",
    "",
    "OF",
    "SF",
    "FALSE",
    "FALSE"
  ]

  @footer_row [
    "Row",
    "Level",
    "#N/A",
    "",
    "",
    "",
    "",
    "",
    "",
    "Row",
    "Level",
    "#N/A",
    "",
    "",
    "",
    "",
    "",
    "",
    "Row",
    "Level",
    "#N/A",
    "",
    "",
    "",
    "",
    "",
    "",
    "Row",
    "Level",
    "#N/A",
    "",
    "",
    "",
    "",
    "",
    "",
    "Row",
    "Level",
    "#N/A",
    "",
    "",
    "",
    "",
    "",
    ""
  ]

  describe "parse/1" do
    test "parses a complete set of rows with legend, header, HM and LM players" do
      rows = [
        @legend_row,
        @separator_row,
        @header_row,
        @player_row_hm,
        @player_row_lm,
        @footer_row
      ]

      result = Parser.parse(rows)

      assert length(result) == 10

      first = Enum.at(result, 0)
      assert first.name == "Andrew Walters"
      assert first.league_level == "HM"
      assert first.position == "P"
      assert first.mlb_team == "CLE"
      assert first.owner_csv_name == "Flex"

      second = Enum.at(result, 1)
      assert second.name == "Bryan Ramos"
      assert second.owner_csv_name == "Newton"

      lm_first = Enum.at(result, 5)
      assert lm_first.name == "Brandon Clarke"
      assert lm_first.league_level == "LM"
      assert lm_first.owner_csv_name == "Flex"
    end

    test "skips legend rows" do
      rows = [
        @legend_row,
        @legend_row,
        @separator_row,
        @header_row,
        @player_row_hm
      ]

      result = Parser.parse(rows)
      assert length(result) == 5
    end

    test "skips empty player slots (blank names)" do
      rows = [
        @header_row,
        @partial_player_row
      ]

      result = Parser.parse(rows)

      assert length(result) == 2
      names = Enum.map(result, & &1.name)
      assert "Emmanuel Rodriguez" in names
      assert "Braden Montgomery" in names
    end

    test "handles multiple team groups with separate headers" do
      rows = [
        @header_row,
        @player_row_hm,
        @second_header_row,
        @second_player_row
      ]

      result = Parser.parse(rows)

      group1_players =
        Enum.filter(result, &(&1.owner_csv_name in ["Flex", "Newton", "RKR", "Kaminski", "Ian"]))

      group2_players =
        Enum.filter(
          result,
          &(&1.owner_csv_name in ["TeamSix", "TeamSeven", "TeamEight", "TeamNine", "TeamTen"])
        )

      assert length(group1_players) == 5
      assert length(group2_players) == 5

      six = Enum.find(result, &(&1.name == "Player Six"))
      assert six.owner_csv_name == "TeamSix"
      assert six.mlb_team == "NYY"
    end

    test "skips footer rows" do
      rows = [
        @header_row,
        @player_row_hm,
        @footer_row
      ]

      result = Parser.parse(rows)
      assert length(result) == 5
    end

    test "returns empty list for rows with no players" do
      rows = [
        @legend_row,
        @separator_row,
        @footer_row
      ]

      result = Parser.parse(rows)
      assert result == []
    end

    test "handles rows shorter than expected by padding" do
      short_header = Enum.take(@header_row, 18)
      short_player = Enum.take(@player_row_hm, 18)

      rows = [short_header, short_player]
      result = Parser.parse(rows)

      assert length(result) == 2
      assert Enum.at(result, 0).name == "Andrew Walters"
      assert Enum.at(result, 1).name == "Bryan Ramos"
    end

    test "correctly associates owners across HM and LM sections" do
      rows = [
        @header_row,
        @player_row_hm,
        @player_row_lm
      ]

      result = Parser.parse(rows)

      flex_players = Enum.filter(result, &(&1.owner_csv_name == "Flex"))
      assert length(flex_players) == 2
      assert Enum.any?(flex_players, &(&1.league_level == "HM"))
      assert Enum.any?(flex_players, &(&1.league_level == "LM"))
    end
  end

  describe "classify_row/1" do
    test "classifies header row" do
      chunks = Enum.chunk_every(@header_row, 9)
      assert Parser.classify_row(chunks) == :header
    end

    test "classifies player row" do
      chunks = Enum.chunk_every(@player_row_hm, 9)
      assert Parser.classify_row(chunks) == :player
    end

    test "classifies legend row as skip" do
      chunks = Enum.chunk_every(@legend_row, 9)
      assert Parser.classify_row(chunks) == :skip
    end

    test "classifies footer row as skip" do
      chunks = Enum.chunk_every(@footer_row, 9)
      assert Parser.classify_row(chunks) == :skip
    end

    test "classifies separator row as skip" do
      chunks = Enum.chunk_every(@separator_row, 9)
      assert Parser.classify_row(chunks) == :skip
    end
  end
end
