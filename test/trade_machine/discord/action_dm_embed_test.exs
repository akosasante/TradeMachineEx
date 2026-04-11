defmodule TradeMachine.Discord.ActionDmEmbedTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.ActionDmEmbed

  describe "build_request_embed/4" do
    test "single recipient copy" do
      embed =
        ActionDmEmbed.build_request_embed(
          "Alice",
          ["Bob"],
          "https://example.com/accept",
          "https://example.com/decline"
        )

      assert embed.title == "TradeMachine — action needed"
      assert embed.color == 0x3498DB
      assert embed.description =~ "Alice requested a trade with you"
      refute embed.description =~ "and others"
      assert embed.description =~ "[Accept](https://example.com/accept)"
      assert embed.description =~ "[Decline](https://example.com/decline)"
    end

    test "multiple recipients copy" do
      embed =
        ActionDmEmbed.build_request_embed(
          "Alice",
          ["Bob", "Carol"],
          "https://example.com/a",
          "https://example.com/d"
        )

      assert embed.description =~ "Alice requested a trade with you and others"
    end
  end

  describe "build_submit_embed/2" do
    test "single recipient uses their name" do
      embed =
        ActionDmEmbed.build_submit_embed(
          ["Bob"],
          "https://example.com/submit"
        )

      assert embed.title == "TradeMachine — submit your trade"
      assert embed.description =~ "Bob accepted your trade proposal"
      assert embed.description =~ "[Submit trade](https://example.com/submit)"
    end

    test "multiple recipients uses generic line" do
      embed =
        ActionDmEmbed.build_submit_embed(
          ["Bob", "Carol"],
          "https://example.com/submit"
        )

      assert embed.description =~ "Recipients accepted your trade proposal"
      refute embed.description =~ "Bob accepted"
    end
  end

  describe "build_declined_embed/3" do
    test "creator sees decliner name and view link" do
      embed =
        ActionDmEmbed.build_declined_embed(
          "Pat",
          true,
          "https://example.com/view"
        )

      assert embed.title == "TradeMachine — trade declined"
      assert embed.description =~ "Your trade proposal was declined by Pat"
      assert embed.description =~ "[View trade](https://example.com/view)"
    end

    test "non-creator copy" do
      embed = ActionDmEmbed.build_declined_embed("Pat", false, nil)

      assert embed.description =~ "A trade you were part of was declined by Pat"
      refute embed.description =~ "[View trade]"
    end

    test "nil declined_by becomes Someone" do
      embed = ActionDmEmbed.build_declined_embed(nil, true, nil)

      assert embed.description =~ "declined by Someone"
    end

    test "empty view_url omits link" do
      embed = ActionDmEmbed.build_declined_embed("Pat", true, "")

      refute embed.description =~ "[View trade]"
    end

    test "non-binary view_url omits link" do
      embed = ActionDmEmbed.build_declined_embed("Pat", false, :not_a_url)

      refute embed.description =~ "[View trade]"
    end
  end
end
