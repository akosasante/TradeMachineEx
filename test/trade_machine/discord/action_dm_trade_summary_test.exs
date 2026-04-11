defmodule TradeMachine.Discord.ActionDmTradeSummaryTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.ActionDmTradeSummary

  describe "embed_fields_for_items/3" do
    test "groups majors by receiving team" do
      majors = [
        %{name: "Mike Trout", sender: "Team A", recipient: "Team B"}
      ]

      [field] = ActionDmTradeSummary.embed_fields_for_items(majors, [], [])

      assert field.name == "Receiving: Team B"
      assert field.inline == false
      assert field.value =~ "Mike Trout"
      assert field.value =~ "Team A"
      assert field.value =~ "• "
    end

    test "groups minors the same way as majors" do
      minors = [
        %{name: "Prospect X", sender: "Squad A", recipient: "Squad B"}
      ]

      [field] = ActionDmTradeSummary.embed_fields_for_items([], minors, [])

      assert field.name =~ "Squad B"
      assert field.value =~ "Prospect X"
    end

    test "combines majors, minors, and picks for the same recipient into one field" do
      majors = [%{name: "M1", sender: "A", recipient: "T"}]
      minors = [%{name: "m1", sender: "A", recipient: "T"}]

      picks = [
        %{
          type: "MAJORS",
          round: 1,
          sender: "A",
          recipient: "T",
          original_owner: "Orig",
          owned_by: nil
        }
      ]

      [field] = ActionDmTradeSummary.embed_fields_for_items(majors, minors, picks)

      assert field.value =~ "M1 from A"
      assert field.value =~ "m1 from A"
      assert field.value =~ "1st round Majors pick"
    end

    test "formats HIGH and LOW pick types" do
      high = %{
        type: "HIGH",
        round: 2,
        sender: "From",
        recipient: "To",
        original_owner: "O",
        owned_by: nil
      }

      low = %{
        type: "LOW",
        round: 4,
        sender: "From2",
        recipient: "To2",
        original_owner: "O2",
        owned_by: nil
      }

      [f1] = ActionDmTradeSummary.embed_fields_for_items([], [], [high])
      assert f1.value =~ "High Minors"

      [f2] = ActionDmTradeSummary.embed_fields_for_items([], [], [low])
      assert f2.value =~ "Low Minors"
    end

    test "uses 11th/12th/13th ordinal suffixes for picks" do
      pick = %{
        type: "MAJORS",
        round: 11,
        sender: "S",
        recipient: "R",
        original_owner: "O",
        owned_by: nil
      }

      [field] = ActionDmTradeSummary.embed_fields_for_items([], [], [pick])
      assert field.value =~ "11th round"
    end

    test "resolves original_owner from map shape (hydrated DB JSON)" do
      pick = %{
        type: "MAJORS",
        round: 1,
        sender: "S",
        recipient: "R",
        original_owner: %{"name" => "Dynasty Kings"},
        owned_by: nil
      }

      [field] = ActionDmTradeSummary.embed_fields_for_items([], [], [pick])
      assert field.value =~ "Dynasty Kings"
    end

    test "nil and empty recipients map to Unknown team label" do
      majors = [
        %{name: "P1", sender: "S", recipient: nil},
        %{name: "P2", sender: "S", recipient: ""}
      ]

      [field] = ActionDmTradeSummary.embed_fields_for_items(majors, [], [])

      assert field.name =~ "Unknown team"
      assert field.value =~ "P1"
      assert field.value =~ "P2"
    end

    test "sorts multiple receiving teams alphabetically by team name" do
      majors = [
        %{name: "a", sender: "x", recipient: "Zebra"},
        %{name: "b", sender: "x", recipient: "Alpha"}
      ]

      [first, second] = ActionDmTradeSummary.embed_fields_for_items(majors, [], [])

      assert first.name =~ "Alpha"
      assert second.name =~ "Zebra"
    end

    test "returns at most 8 receiving-team fields" do
      majors =
        for i <- 0..9 do
          %{
            name: "Player#{i}",
            sender: "S",
            recipient: "Team-#{String.pad_leading("#{i}", 2, "0")}"
          }
        end

      fields = ActionDmTradeSummary.embed_fields_for_items(majors, [], [])
      assert length(fields) == 8
    end

    test "truncates field value when bullet list exceeds Discord limit" do
      long_line = String.duplicate("x", 120)

      majors =
        for _ <- 1..20 do
          %{name: "n", sender: "s", recipient: "OneTeam"}
        end
        |> Enum.map(fn m -> %{m | name: long_line} end)

      [field] = ActionDmTradeSummary.embed_fields_for_items(majors, [], [])

      assert String.length(field.value) <= 1024
      assert String.ends_with?(field.value, "…")
    end

    test "truncates very long team name in field title" do
      long_team = String.duplicate("T", 300)

      majors = [%{name: "P", sender: "S", recipient: long_team}]
      [field] = ActionDmTradeSummary.embed_fields_for_items(majors, [], [])

      assert String.length(field.name) <= 256
      assert String.ends_with?(field.name, "…")
    end

    test "empty lists show placeholder field" do
      [field] = ActionDmTradeSummary.embed_fields_for_items([], [], [])
      assert field.name == "Trade details"
      assert field.value =~ "No player or pick"
    end

    test "nil traded lists show placeholder field" do
      [field] = ActionDmTradeSummary.embed_fields_for_items(nil, nil, nil)
      assert field.name == "Trade details"
      assert field.value =~ "No player or pick"
    end
  end
end
