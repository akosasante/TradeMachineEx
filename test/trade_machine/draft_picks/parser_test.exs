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
  # 10 major league picks (rounds "1".."10"), 1 HM pick ("HM1"), 4 LM picks ("LM1", "LM3", "LM4", "LM5")
  # ---------------------------------------------------------------------------

  @group1_owners ["Alice", "Bob", "Carol", "Dave", "Eve"]

  defp group1_rows do
    owner_row = build_owner_header_row(@group1_owners)

    # 10 major league picks (indices 0–9)
    ml_picks =
      for i <- 1..10 do
        build_pick_row([
          {"#{i}", "Alice", i * 10, "Alice"},
          {"#{i}", "Bob", i * 10 + 1, "Bob"},
          {"#{i}", "Carol", i * 10 + 2, "Carol"},
          {"#{i}", "Dave", i * 10 + 3, "Dave"},
          {"#{i}", "Eve", i * 10 + 4, "Eve"}
        ])
      end

    # 1 HM pick (index 10)
    hm_pick =
      build_pick_row([
        {"HM1", "Alice", 110, "Alice"},
        {"HM1", "Bob", 111, "Bob"},
        {"HM1", "Carol", 112, "Carol"},
        {"HM1", "Dave", 113, "Dave"},
        {"HM1", "Eve", 114, "Eve"}
      ])

    # 4 LM picks (indices 11–14)
    lm_picks =
      Enum.map(["LM1", "LM3", "LM4", "LM5"], fn label ->
        n = label |> String.replace("LM", "") |> String.to_integer()

        build_pick_row([
          {label, "Alice", n * 10, "Alice"},
          {label, "Bob", n * 10 + 1, "Bob"},
          {label, "Carol", n * 10 + 2, "Carol"},
          {label, "Dave", n * 10 + 3, "Dave"},
          {label, "Eve", n * 10 + 4, "Eve"}
        ])
      end)

    [owner_row, @round_header_row] ++ ml_picks ++ [hm_pick] ++ lm_picks
  end

  # ---------------------------------------------------------------------------
  # Group 2 fixture: 5 owners WITHOUT "Round" header row (groups 2–4)
  # ---------------------------------------------------------------------------

  @group2_owners ["Frank", "Grace", "Hank", "Iris", "Jake"]

  defp group2_rows do
    owner_row = build_owner_header_row(@group2_owners)

    ml_picks =
      for i <- 1..10 do
        build_pick_row([
          {"#{i}", "Frank", i * 10, "Frank"},
          {"#{i}", "Grace", i * 10 + 1, "Grace"},
          {"#{i}", "Hank", i * 10 + 2, "Hank"},
          {"#{i}", "Iris", i * 10 + 3, "Iris"},
          {"#{i}", "Jake", i * 10 + 4, "Jake"}
        ])
      end

    hm_pick =
      build_pick_row([
        {"HM1", "Frank", 110, "Frank"},
        {"HM1", "Grace", 111, "Grace"},
        {"HM1", "Hank", 112, "Hank"},
        {"HM1", "Iris", 113, "Iris"},
        {"HM1", "Jake", 114, "Jake"}
      ])

    lm_picks =
      Enum.map(["LM1", "LM3", "LM4", "LM5"], fn label ->
        n = label |> String.replace("LM", "") |> String.to_integer()

        build_pick_row([
          {label, "Frank", n * 10, "Frank"},
          {label, "Grace", n * 10 + 1, "Grace"},
          {label, "Hank", n * 10 + 2, "Hank"},
          {label, "Iris", n * 10 + 3, "Iris"},
          {label, "Jake", n * 10 + 4, "Jake"}
        ])
      end)

    [owner_row] ++ ml_picks ++ [hm_pick] ++ lm_picks
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
      # 15 pick rows × 5 owners = 75
      assert length(picks) == 75
    end

    test "parses 50 major league picks from one group", %{picks: picks} do
      majors = Enum.filter(picks, &(&1.type == :majors))
      assert length(majors) == 50
    end

    test "parses 5 high-minor picks from one group", %{picks: picks} do
      high = Enum.filter(picks, &(&1.type == :high))
      assert length(high) == 5
    end

    test "parses 20 low-minor picks from one group", %{picks: picks} do
      low = Enum.filter(picks, &(&1.type == :low))
      assert length(low) == 20
    end

    test "extracts original_owner_csv correctly", %{picks: picks} do
      alice_picks = Enum.filter(picks, &(&1.original_owner_csv == "Alice"))
      assert length(alice_picks) == 15
    end

    test "extracts current_owner_csv correctly", %{picks: picks} do
      alice_picks = Enum.filter(picks, &(&1.current_owner_csv == "Alice"))
      assert length(alice_picks) == 15
    end

    test "extracts round as Decimal for major league picks", %{picks: picks} do
      first = hd(picks)
      assert %Decimal{} = first.round
      assert Decimal.compare(first.round, Decimal.new(0)) == :gt
    end

    test "extracts round as Decimal for HM pick", %{picks: picks} do
      hm = Enum.find(picks, &(&1.type == :high))
      assert %Decimal{} = hm.round
      assert Decimal.equal?(hm.round, Decimal.new(1))
    end

    test "extracts round as Decimal for LM picks", %{picks: picks} do
      lm_rounds =
        picks
        |> Enum.filter(&(&1.type == :low and &1.original_owner_csv == "Alice"))
        |> Enum.map(& &1.round)
        |> Enum.map(&Decimal.to_integer/1)
        |> Enum.sort()

      assert lm_rounds == [1, 3, 4, 5]
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
      assert length(picks) == 75
    end

    test "parses 50 major league picks without Round header", %{picks: picks} do
      majors = Enum.filter(picks, &(&1.type == :majors))
      assert length(majors) == 50
    end

    test "parses 5 high-minor picks without Round header", %{picks: picks} do
      high = Enum.filter(picks, &(&1.type == :high))
      assert length(high) == 5
    end

    test "parses 20 low-minor picks without Round header", %{picks: picks} do
      low = Enum.filter(picks, &(&1.type == :low))
      assert length(low) == 20
    end

    test "extracts correct owner names from group 2", %{picks: picks} do
      frank_picks = Enum.filter(picks, &(&1.original_owner_csv == "Frank"))
      assert length(frank_picks) == 15
    end
  end

  describe "parse/1 - two groups combined" do
    test "parses both groups correctly" do
      rows = group1_rows() ++ [@legend_row] ++ group2_rows()
      picks = Parser.parse(rows)
      assert length(picks) == 150

      owners = picks |> Enum.map(& &1.original_owner_csv) |> Enum.uniq() |> Enum.sort()
      assert owners == Enum.sort(@group1_owners ++ @group2_owners)
    end
  end

  describe "parse/1 - cleared picks" do
    test "excludes picks with OVR = 0" do
      owner_row = build_owner_header_row(["Alice", "Bob", "Carol", "Dave", "Eve"])

      cleared_row =
        cleared_pick_row([
          {"1", "Alice", 0, "Alice"},
          {"1", "Bob", 0, "Bob"},
          {"1", "Carol", 0, "Carol"},
          {"1", "Dave", 0, "Dave"},
          {"1", "Eve", 0, "Eve"}
        ])

      valid_row =
        build_pick_row([
          {"2", "Alice", 50, "Alice"},
          {"2", "Bob", 51, "Bob"},
          {"2", "Carol", 52, "Carol"},
          {"2", "Dave", 53, "Dave"},
          {"2", "Eve", 54, "Eve"}
        ])

      remaining_rows =
        for i <- 3..15 do
          label =
            cond do
              i <= 10 -> "#{i}"
              i == 11 -> "HM1"
              true -> "LM#{i - 10}"
            end

          build_pick_row([
            {label, "Alice", i * 10, "Alice"},
            {label, "Bob", i * 10 + 1, "Bob"},
            {label, "Carol", i * 10 + 2, "Carol"},
            {label, "Dave", i * 10 + 3, "Dave"},
            {label, "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, cleared_row, valid_row] ++ remaining_rows
      picks = Parser.parse(rows)

      # 15 rows: row 0 cleared (0 picks), rows 1–14 valid (14 * 5 = 70)
      assert length(picks) == 70
    end

    test "excludes picks with negative OVR" do
      owner_row = build_owner_header_row(["Alice", "Bob", "Carol", "Dave", "Eve"])

      neg_row =
        cleared_pick_row([
          {"1", "Alice", -8, "Alice"},
          {"1", "Bob", -8, "Bob"},
          {"1", "Carol", -8, "Carol"},
          {"1", "Dave", -8, "Dave"},
          {"1", "Eve", -8, "Eve"}
        ])

      remaining_rows =
        for i <- 2..15 do
          label =
            cond do
              i <= 10 -> "#{i}"
              i == 11 -> "HM1"
              true -> "LM#{i - 10}"
            end

          build_pick_row([
            {label, "Alice", i * 10, "Alice"},
            {label, "Bob", i * 10 + 1, "Bob"},
            {label, "Carol", i * 10 + 2, "Carol"},
            {label, "Dave", i * 10 + 3, "Dave"},
            {label, "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, neg_row] ++ remaining_rows
      picks = Parser.parse(rows)
      # row 0 cleared, rows 1–14 valid (14 * 5 = 70)
      assert length(picks) == 70
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
        for i <- 2..15 do
          label =
            cond do
              i <= 10 -> "#{i}"
              i == 11 -> "HM1"
              true -> "LM#{i - 10}"
            end

          build_pick_row([
            {label, "Alice", i * 10, "Alice"},
            {label, "Bob", i * 10 + 1, "Bob"},
            {label, "Carol", i * 10 + 2, "Carol"},
            {label, "Dave", i * 10 + 3, "Dave"},
            {label, "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, blank_round_row] ++ remaining_rows
      picks = Parser.parse(rows)
      assert length(picks) == 70
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
          {"1", "Alice", 5, "Alice"},
          # Bob's block: Bob now holds Alice's pick (original = Alice, block header = Bob)
          {"1", "Alice", 6, "Bob"},
          {"1", "Carol", 7, "Carol"},
          {"1", "Dave", 8, "Dave"},
          {"1", "Eve", 9, "Eve"}
        ])

      remaining_rows =
        for i <- 2..15 do
          label =
            cond do
              i <= 10 -> "#{i}"
              i == 11 -> "HM1"
              true -> "LM#{i - 10}"
            end

          build_pick_row([
            {label, "Alice", i * 10, "Alice"},
            {label, "Bob", i * 10 + 1, "Bob"},
            {label, "Carol", i * 10 + 2, "Carol"},
            {label, "Dave", i * 10 + 3, "Dave"},
            {label, "Eve", i * 10 + 4, "Eve"}
          ])
        end

      rows = [owner_row, @round_header_row, traded_row] ++ remaining_rows
      picks = Parser.parse(rows)

      # Alice's pick in Bob's block: orig = Alice, current = Bob (from block header)
      traded_pick =
        Enum.find(picks, &(&1.original_owner_csv == "Alice" && &1.current_owner_csv == "Bob"))

      assert traded_pick != nil
      assert Decimal.equal?(traded_pick.round, Decimal.new(1))
      assert traded_pick.pick_number == 6
    end
  end

  describe "parse/1 - short rows" do
    test "handles rows shorter than expected column count" do
      owner_row = ["Alice"]

      pick_row = ["1", "Alice", "", "10", "Alice"]

      rows = [owner_row, @round_header_row] ++ [pick_row] ++ for(_ <- 2..15, do: @legend_row)
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
