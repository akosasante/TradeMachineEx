defmodule TradeMachine.Discord.EmbedBuilderTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.EmbedBuilder

  describe "build_trade_embed/1" do
    test "returns embed with correct title" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.title == "🔊  A Trade Has Been Submitted  🔊"
    end

    test "returns embed with correct color" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.color == 0x3498DB
    end

    test "returns embed with footer" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.footer.text =~ "FlexFoxFantasy TradeMachine"
    end

    test "description contains date timestamp" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.description =~ ~r/<t:\d+:D>/
    end

    test "description contains uphold timestamp" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.description =~ ~r/<t:\d+:F>/
    end

    test "description contains creator mention" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.description =~ "@Ryan Neeson"
    end

    test "description contains recipient mention" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.description =~ "@Mikey"
    end

    test "description contains participant receives sections" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.description =~ "**Ryan** receives:"
      assert embed.description =~ "**Mikey** receives:"
    end

    test "description contains formatted player names" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.description =~ "Ketel Marte"
      assert embed.description =~ "George Kirby"
    end

    test "description contains formatted pick info" do
      embed = EmbedBuilder.build_trade_embed(sample_trade_data())
      assert embed.description =~ "Major League pick"
    end

    test "handles trade with three teams" do
      embed = EmbedBuilder.build_trade_embed(three_team_trade_data())
      assert embed.description =~ "**Ryan** receives:"
      assert embed.description =~ "**Mikey** receives:"
      assert embed.description =~ "**James** receives:"
    end
  end

  describe "calculate_uphold_timestamp/1" do
    test "returns a future timestamp" do
      now = DateTime.utc_now()
      result = EmbedBuilder.calculate_uphold_timestamp(now)
      assert result > DateTime.to_unix(now)
    end

    test "trade submitted before 11pm gets next day 11pm" do
      # March 15 2026, 10:00 PM Eastern = March 16 03:00 UTC (EDT)
      {:ok, now} = DateTime.new(~D[2026-03-16], ~T[03:00:00], "Etc/UTC")
      result = EmbedBuilder.calculate_uphold_timestamp(now)

      # Should be March 16 11pm Eastern = March 17 03:00 UTC
      {:ok, expected} = DateTime.new(~D[2026-03-17], ~T[03:00:00], "Etc/UTC")
      assert result == DateTime.to_unix(expected)
    end

    test "trade submitted after 11pm needs two days" do
      # March 15 2026, 11:30 PM Eastern = March 16 03:30 UTC (EDT)
      {:ok, now} = DateTime.new(~D[2026-03-16], ~T[03:30:00], "Etc/UTC")
      result = EmbedBuilder.calculate_uphold_timestamp(now)

      # 11pm on the 16th is only ~23.5hrs away, so next eligible is March 17 11pm
      {:ok, expected} = DateTime.new(~D[2026-03-18], ~T[03:00:00], "Etc/UTC")
      assert result == DateTime.to_unix(expected)
    end

    test "trade submitted at exactly 11pm needs two days" do
      # March 15 2026, 11:00 PM Eastern = March 16 03:00 UTC (EDT)
      # Today's 11pm has already arrived (equal), so next_11pm is tomorrow
      # Tomorrow's 11pm = March 16 11pm = only 24 hours away (equal to minimum)
      {:ok, now} = DateTime.new(~D[2026-03-16], ~T[03:00:00.000001], "Etc/UTC")
      result = EmbedBuilder.calculate_uphold_timestamp(now)

      # If submitted at 11:00:00.000001 PM, today's 11pm has passed,
      # tomorrow's 11pm is ~23:59:59 away (less than 24h), so it goes to day after
      {:ok, expected} = DateTime.new(~D[2026-03-18], ~T[03:00:00], "Etc/UTC")
      assert result == DateTime.to_unix(expected)
    end
  end

  defp sample_trade_data do
    %{
      trade_id: "test-id",
      date_created: ~U[2026-03-15 20:00:00Z],
      creator: %{
        owners: [%{display_name: "Ryan Neeson", discord_user_id: nil, csv_name: "Ryan"}]
      },
      recipient_owners: [
        %{display_name: "Mikey", discord_user_id: nil, csv_name: "Mikey"}
      ],
      participants: [
        %{
          display_name: "Ryan",
          items: [
            %{type: :major_player, name: "Ketel Marte", mlb_team: "ARI", position: "2B"},
            %{type: :pick, owner_name: "Mikey", round: 2, pick_type: :majors, season: 2026}
          ]
        },
        %{
          display_name: "Mikey",
          items: [
            %{type: :major_player, name: "George Kirby", mlb_team: "SEA", position: "SP"},
            %{
              type: :minor_player,
              name: "Patrick Forbes",
              level: nil,
              mlb_team: nil,
              position: nil
            }
          ]
        }
      ]
    }
  end

  defp three_team_trade_data do
    %{
      trade_id: "test-3-team",
      date_created: ~U[2026-03-15 20:00:00Z],
      creator: %{
        owners: [%{display_name: "Ryan Neeson", discord_user_id: nil, csv_name: "Ryan"}]
      },
      recipient_owners: [
        %{display_name: "Mikey", discord_user_id: nil, csv_name: "Mikey"},
        %{display_name: "James", discord_user_id: nil, csv_name: "James"}
      ],
      participants: [
        %{
          display_name: "Ryan",
          items: [
            %{type: :major_player, name: "Ketel Marte", mlb_team: "ARI", position: "2B"}
          ]
        },
        %{
          display_name: "Mikey",
          items: [
            %{type: :major_player, name: "George Kirby", mlb_team: "SEA", position: "SP"}
          ]
        },
        %{
          display_name: "James",
          items: [
            %{type: :pick, owner_name: "Ryan", round: 1, pick_type: :low, season: 2026}
          ]
        }
      ]
    }
  end
end
