defmodule TradeMachine.DraftPicks.ParserTest do
  use ExUnit.Case, async: true

  alias TradeMachine.DraftPicks.Parser

  # ---------------------------------------------------------------------------
  # Fixture helpers
  # ---------------------------------------------------------------------------

  # Build a single 35-column row for one group of 5 owners.
  # Each owner takes 7 columns: [round, orig_owner, ignored, ovr, curr_owner, ignored, ignored]
  defp build_owner_header_row(owners) do
    owners
    |> Enum.map(fn name -> [name, "", "", "", "", "", ""] end)
    |> List.flatten()
  end

  defp build_pick_row(picks) do
    # picks is a list of {round, orig_owner, ovr, curr_owner} for each of the 5 owner slots
    picks
    |> Enum.map(fn {round, orig, ovr, curr} ->
      [round, orig, "", to_string(ovr), curr, "", ""]
    end)
    |> List.flatten()
  end

  defp cleared_pick_row(picks) do
    # A cleared pick has OVR <= 0 or round is blank/non-numeric
    picks
    |> Enum.map(fn {round, orig, ovr, curr} ->
      [round, orig, "", to_string(ovr), curr, "", ""]
    end)
    |> List.flatten()
  end

  @legend_row List.duplicate("", 35)
  @draft_picks_header ["Draft Picks"] ++ List.duplicate("", 34)
  @round_header_row ["Round"] ++ List.duplicate("", 34)
  @grey_row ["GREY | something"] ++ List.duplicate("", 34)

  # ---------------------------------------------------------------------------
  # Group 1 fixture: 5 owners with "Round" column header row
  # ---------------------------------------------------------------------------

  @group1_owners ["Alice", "Bob", "Carol", "Dave", "Eve"]

  defp group1_rows do
    owner_row = build_owner_header_row(@group1_owners)

    # 10 ML picks (indices 0–9), 2 HM picks (10–11), 5 LM picks (12–16)
    ml_picks =
      for i <- 1..10 do
        build_pick_row([
          {"#{i}.0", "Alice", i * 10, "Alice"},
          {"#{i}.0", "Bob", i * 10 + 1, "Bob"},
          {"#{i}.0", "Carol", i * 10 + 2, "Carol"},
          {"#{i}.0", "Dave", i * 10 + 3, "Dave"},
          {"#{i}.0", "Eve", i * 10 + 4, "Eve"}
        ])
      end

    hm_picks =
      for i <- 11..12 do
        build_pick_row([
          {"#{i}.0", "Alice", i * 10, "Alice"},
          {"#{i}.0", "Bob", i * 10 + 1, "Bob"},
          {"#{i}.0", "Carol", i * 10 + 2, "Carol"},
          {"#{i}.0", "Dave", i * 10 + 3, "Dave"},
          {"#{i}.0", "Eve", i * 10 + 4, "Eve"}
        ])
      end

    lm_picks =
      for i <- 13..17 do
        build_pick_row([
          {"#{i}.0", "Alice", i * 10, "Alice"},
          {"#{i}.0", "Bob", i * 10 + 1, "Bob"},
          {"#{i}.0", "Carol", i * 10 + 2, "Carol"},
          {"#{i}.0", "Dave", i * 10 + 3, "Dave"},
          {"#{i}.0", "Eve", i * 10 + 4, "Eve"}
        ])
      end

    [owner_row, @round_header_row] ++ ml_picks ++ hm_picks ++ lm_picks
  end

  # ---------------------------------------------------------------------------
  # Group 2 fixture: 5 owners WITHOUT "Round" header row (groups 2–4)
  # ---------------------------------------------------------------------------

  @group2_owners ["Frank", "Grace", "Hank", "Iris", "Jake"]

  defp group2_rows do
    owner_row = build_owner_header_row(@group2_owners)

    all_picks =
      for i <- 1..17 do
        build_pick_row([
          {"#{i}.0", "Frank", i * 10, "Frank"},
          {"#{i}.0", "Grace", i * 10 + 1, "Grace"},
          {"#{i}.0", "Hank", i * 10 + 2, "Hank"},
          {"#{i}.0", "Iris", i * 10 + 3, "Iris"},
          {"#{i}.0", "Jake", i * 10 + 4, "Jake"}
        ])
      end

    [owner_row] ++ all_picks
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "parse/1 - basic structure" do
    test "returns empty list for empty rows" do
      assert Parser.parse([]) == []
    end

    test "skips legend and separator rows" do
      rows = [@legend_row, @legend_row, @draft_picks_header, @grey_row]
      assert Parser.parse(rows) == []
    end

    test "returns empty list for rows with only a Round header" do
      assert Parser.parse([@round_header_row]) == []
    end
  end

  describe "parse/1 - group 1 (with Round header row)" do
    setup do
      rows = [@legend_row, @draft_picks_header] ++ group1_rows()
      picks = Parser.parse(rows)
      %{picks: picks}
    end

    test "parses correct total count from one group", %{picks: picks} do
      assert length(picks) == 85
    end

    test "parses 50 major league picks from one group", %{picks: picks} do
      majors = Enum.filter(picks, &(&1.type == :majors))
      assert length(majors) == 50
    end

    test "parses 10 high-minor picks from one group", %{picks: picks} do
      high = Enum.filter(picks, &(&1.type == :high))
      assert length(high) == 10
    end

    test "parses 25 low-minor picks from one group", %{picks: picks} do
      low = Enum.filter(picks, &(&1.type == :low))
      assert length(low) == 25
    end

    test "extracts original_owner_csv correctly", %{picks: picks} do
      alice_picks = Enum.filter(picks, &(&1.original_owner_csv == "Alice"))
      assert length(alice_picks) == 17
    end

    test "extracts current_owner_csv correctly", %{picks: picks} do
      alice_picks = Enum.filter(picks, &(&1.current_owner_csv == "Alice"))
      assert length(alice_picks) == 17
    end

    test "extracts round as Decimal", %{picks: picks} do
      first = hd(picks)
      assert %Decimal{} = first.round
      assert Decimal.compare(first.round, Decimal.new(0)) == :gt
    end

    test "extracts pick_number as integer", %{picks: picks} do
      first = hd(picks)
      assert is_integer(first.pick_number)
      assert first.pick_number > 0
    end
  end

  describe "parse/1 - group 2 (without Round header row)" do
    setup do
      picks = Parser.parse(group2_rows())
      %{picks: picks}
    end

    test "parses correct total count without Round header", %{picks: picks} do
      assert length(picks) == 85
    end

    test "parses 50 major league picks without Round header", %{picks: picks} do
      majors = Enum.filter(picks, &(&1.type == :majors))
      assert length(majors) == 50
    end

    test "parses 10 high-minor picks without Round header", %{picks: picks} do
      high = Enum.filter(picks, &(&1.type == :high))
      assert length(high) == 10
    end

    test "parses 25 low-minor picks without Round header", %{picks: picks} do
      low = Enum.filter(picks, &(&1.type == :low))
      assert length(low) == 25
    end

    test "extracts correct owner names from group 2", %{picks: picks} do
      frank_picks = Enum.filter(picks, &(&1.original_owner_csv == "Frank"))
      assert length(frank_picks) == 17
    end
  end

  describe "parse/1 - two groups combined" do
    test "parses both groups correctly" do
      rows = group1_rows() ++ [@legend_row] ++ group2_rows()
      picks = Parser.parse(rows)
      assert length(picks) == 170

      owners = picks |> Enum.map(& &1.original_owner_csv) |> Enum.uniq() |> Enum.sort()
      assert owners == Enum.sort(@group1_owners ++ @group2_owners)
    end
  end

  describe "parse/1 - cleared picks" do
    test "excludes picks with OVR = 0" do
      owner_row = build_owner_header_row(["Alice", "Bob", "Carol", "Dave", "Eve"])

      cleared_row =
        cleared_pick_row([
          {"1.0", "Alice", 0, "Alice"},
          {"1.0", "Bob", 0, "Bob"},
          {"1.0", "Carol", 0, "Carol"},
          {"1.0", "Dave", 0, "Dave"},
          {"1.0", "Eve", 0, "Eve"}
        ])

      valid_row =
        build_pick_row([
          {"2.0", "Alice", 50, "Alice"},
          {"2.0", "Bob", 51, "Bob"},
          {"2.0", "Carol", 52, "Carol"},
          {"2.0", "Dave", 53, "Dave"},
          {"2.0", "Eve", 54, "Eve"}
        ])

      remaining_rows =
        for i <- 3..17 do
          build_pick_row([
            {"#{i}.0", "Alice", i * 10, "Alice"},
            {"#{i}.0", "Bob", i * 10 + 1, "Bob"},
            {"#{i}.0", "Carol", i * 10 + 2, "Carol"},
            {"#{i}.0", "Dave", i * 10 + 3, "Dave"},
            {"#{i}.0", "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, cleared_row, valid_row] ++ remaining_rows
      picks = Parser.parse(rows)

      # 17 rows: row 0 cleared (0 picks), rows 1–16 valid (5 each = 80)
      assert length(picks) == 80
    end

    test "excludes picks with negative OVR" do
      owner_row = build_owner_header_row(["Alice", "Bob", "Carol", "Dave", "Eve"])

      neg_row =
        cleared_pick_row([
          {"1.0", "Alice", -8, "Alice"},
          {"1.0", "Bob", -8, "Bob"},
          {"1.0", "Carol", -8, "Carol"},
          {"1.0", "Dave", -8, "Dave"},
          {"1.0", "Eve", -8, "Eve"}
        ])

      remaining_rows =
        for i <- 2..17 do
          build_pick_row([
            {"#{i}.0", "Alice", i * 10, "Alice"},
            {"#{i}.0", "Bob", i * 10 + 1, "Bob"},
            {"#{i}.0", "Carol", i * 10 + 2, "Carol"},
            {"#{i}.0", "Dave", i * 10 + 3, "Dave"},
            {"#{i}.0", "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, neg_row] ++ remaining_rows
      picks = Parser.parse(rows)
      # row 0 cleared, rows 1–16 valid (16 * 5 = 80)
      assert length(picks) == 80
    end

    test "excludes picks with blank round cell" do
      owner_row = build_owner_header_row(["Alice", "Bob", "Carol", "Dave", "Eve"])

      blank_round_row =
        cleared_pick_row([
          {"", "Alice", 10, "Alice"},
          {"", "Bob", 11, "Bob"},
          {"", "Carol", 12, "Carol"},
          {"", "Dave", 13, "Dave"},
          {"", "Eve", 14, "Eve"}
        ])

      remaining_rows =
        for i <- 2..17 do
          build_pick_row([
            {"#{i}.0", "Alice", i * 10, "Alice"},
            {"#{i}.0", "Bob", i * 10 + 1, "Bob"},
            {"#{i}.0", "Carol", i * 10 + 2, "Carol"},
            {"#{i}.0", "Dave", i * 10 + 3, "Dave"},
            {"#{i}.0", "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, blank_round_row] ++ remaining_rows
      picks = Parser.parse(rows)
      assert length(picks) == 80
    end
  end

  describe "parse/1 - traded picks" do
    test "current_owner_csv comes from the column block header (not the pick row)" do
      # In the sheet, when Alice trades her round-1 pick to Bob, the pick moves
      # to Bob's column block. The block header IS the current owner. The pick row
      # tracks the original owner in column 1. So Bob's block has a pick where
      # orig_owner = "Alice" and current_owner (from header) = "Bob".
      owner_row = build_owner_header_row(["Alice", "Bob", "Carol", "Dave", "Eve"])

      traded_row =
        build_pick_row([
          # Alice's block: Alice holds her own pick
          {"1.0", "Alice", 5, "Alice"},
          # Bob's block: Bob now holds Alice's pick (original = Alice, block header = Bob)
          {"1.0", "Alice", 6, "Bob"},
          {"1.0", "Carol", 7, "Carol"},
          {"1.0", "Dave", 8, "Dave"},
          {"1.0", "Eve", 9, "Eve"}
        ])

      remaining_rows =
        for i <- 2..17 do
          build_pick_row([
            {"#{i}.0", "Alice", i * 10, "Alice"},
            {"#{i}.0", "Bob", i * 10 + 1, "Bob"},
            {"#{i}.0", "Carol", i * 10 + 2, "Carol"},
            {"#{i}.0", "Dave", i * 10 + 3, "Dave"},
            {"#{i}.0", "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, traded_row] ++ remaining_rows
      picks = Parser.parse(rows)

      # Alice's pick in Bob's block: orig = Alice, current = Bob (from block header)
      traded_pick =
        Enum.find(picks, &(&1.original_owner_csv == "Alice" && &1.current_owner_csv == "Bob"))

      assert traded_pick != nil
      assert Decimal.compare(traded_pick.round, Decimal.new("1.0")) == :eq
      assert traded_pick.pick_number == 6
    end
  end

  describe "parse/1 - short rows" do
    test "handles rows shorter than expected column count" do
      owner_row = ["Alice"]

      pick_row = ["1.0", "Alice", "", "10", "Alice"]

      rows = [owner_row, @round_header_row] ++ [pick_row] ++ for(_ <- 2..17, do: @legend_row)
      # Should not crash; padded short rows are handled gracefully
      picks = Parser.parse(rows)
      assert is_list(picks)
    end
  end

  describe "parse/1 - skip rows" do
    test "ignores GREY / BLUE / RED legend rows" do
      grey = ["GREY | something"] ++ List.duplicate("", 34)
      blue = ["BLUE | else"] ++ List.duplicate("", 34)
      red = ["RED | thing"] ++ List.duplicate("", 34)

      rows = [grey, blue, red]
      assert Parser.parse(rows) == []
    end

    test "ignores Draft Picks header rows" do
      assert Parser.parse([@draft_picks_header]) == []
    end
  end
end
