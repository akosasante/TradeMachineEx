defmodule TradeMachine.Discord.TradeListEmbedBuilderTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Data.Trade
  alias TradeMachine.Discord.TradeListEmbedBuilder

  describe "build/3" do
    test "returns embed with correct title" do
      embed = TradeListEmbedBuilder.build("Test Title", [])
      assert embed.title == "Test Title"
    end

    test "returns embed with correct color" do
      embed = TradeListEmbedBuilder.build("Title", [])
      assert embed.color == 0x3498DB
    end

    test "shows no trades message when list is empty" do
      embed = TradeListEmbedBuilder.build("Empty", [])
      assert embed.description == "_No trades found._"
    end

    test "includes footer with frontend URL" do
      embed = TradeListEmbedBuilder.build("Title", [], frontend_url: "https://example.com")
      assert embed.footer.text == "View all trades at https://example.com/my-trades"
    end

    test "includes generic footer when no frontend URL" do
      embed = TradeListEmbedBuilder.build("Title", [])
      assert embed.footer.text == "View more on the trades app"
    end

    test "shows remaining count in footer when total_count exceeds shown" do
      embed =
        TradeListEmbedBuilder.build("Title", [],
          frontend_url: "https://example.com",
          total_count: 12
        )

      assert embed.footer.text == "and 12 more — view all at https://example.com/my-trades"
    end

    test "shows remaining count with generic footer when no frontend URL" do
      embed = TradeListEmbedBuilder.build("Title", [], total_count: 8)
      assert embed.footer.text == "and 8 more — view all on the trades app"
    end

    test "does not show remaining count when total_count matches shown" do
      embed =
        TradeListEmbedBuilder.build("Title", [],
          frontend_url: "https://example.com",
          total_count: 0
        )

      assert embed.footer.text == "View all trades at https://example.com/my-trades"
    end

    test "description never exceeds 4096 characters" do
      assert String.length(TradeListEmbedBuilder.build("Title", []).description) <= 4096
    end

    test "includes trade header and view link when trades have no participants" do
      trade = %Trade{
        id: "550e8400-e29b-41d4-a716-446655440001",
        status: :requested,
        inserted_at: ~N[2024-06-01 12:00:00],
        participants: [],
        traded_items: []
      }

      embed =
        TradeListEmbedBuilder.build("Title", [trade],
          frontend_url: "https://example.com",
          total_count: 1
        )

      assert embed.description =~ "Requested"
      assert embed.description =~ "View trade"
      assert embed.description =~ "/trades/550e8400-e29b-41d4-a716-446655440001/review"
      assert embed.footer.text == "View all trades at https://example.com/my-trades"
    end

    test "truncates description before Discord limit when many trades are listed" do
      trades =
        for _ <- 1..60 do
          %Trade{
            id: Ecto.UUID.generate(),
            status: :requested,
            inserted_at: ~N[2024-06-01 12:00:00],
            participants: [],
            traded_items: []
          }
        end

      embed = TradeListEmbedBuilder.build("Title", trades, frontend_url: "https://example.com")

      assert String.length(embed.description) < 4096
      assert embed.footer.text =~ "more — view all at"
    end
  end
end
