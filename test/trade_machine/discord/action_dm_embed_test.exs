defmodule TradeMachine.Discord.ActionDmEmbedTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.ActionDmEmbed

  describe "request_action_components/2" do
    test "returns one action row with two link buttons" do
      [row] = ActionDmEmbed.request_action_components("https://ex/a", "https://ex/d")
      assert row.type == 1
      assert length(row.components) == 2
      [accept, decline] = row.components

      for btn <- [accept, decline] do
        assert btn.type == 2
        assert btn.style == 5
        assert is_binary(btn.label)
        assert is_binary(btn.url)
        refute Map.has_key?(btn, :custom_id)
      end

      assert accept.label == "Accept"
      assert accept.url == "https://ex/a"
      assert decline.label == "Decline"
      assert decline.url == "https://ex/d"
    end
  end

  describe "submit_action_components/1" do
    test "returns a single submit link button" do
      [row] = ActionDmEmbed.submit_action_components("https://ex/s")
      assert row.type == 1
      assert [btn] = row.components
      assert btn.label == "Submit trade" and btn.style == 5 and btn.url == "https://ex/s"
      refute Map.has_key?(btn, :custom_id)
    end
  end

  describe "declined_action_components/1" do
    test "returns empty list when no URL" do
      assert ActionDmEmbed.declined_action_components(nil) == []
      assert ActionDmEmbed.declined_action_components("") == []
    end

    test "returns view button when URL present" do
      [row] = ActionDmEmbed.declined_action_components("https://ex/v")
      btn = hd(row.components)
      assert btn.label == "View trade" and btn.style == 5 and btn.url == "https://ex/v"
    end
  end

  describe "build_request_embed/3" do
    test "single recipient copy" do
      embed = ActionDmEmbed.build_request_embed("Alice", ["Bob"], [])

      assert embed.title == "Action Needed"
      assert embed.color == 0x3498DB
      assert embed.description =~ "Alice requested a trade with you"
      refute embed.description =~ "and others"
      assert embed.description =~ "Review what each team would receive"
      refute Map.has_key?(embed, :fields)
    end

    test "includes fields when provided" do
      fields = [%{name: "Receiving: T1", value: "• x", inline: false}]

      embed = ActionDmEmbed.build_request_embed("Alice", ["Bob"], fields)

      assert embed.fields == fields
    end

    test "multiple recipients copy" do
      embed = ActionDmEmbed.build_request_embed("Alice", ["Bob", "Carol"], [])

      assert embed.description =~ "Alice requested a trade with you and others"
    end
  end

  describe "build_submit_embed/2" do
    test "single recipient uses their name" do
      embed = ActionDmEmbed.build_submit_embed(["Bob"], [])

      assert embed.title == "Submit Your Trade"
      assert embed.description =~ "Bob accepted your trade proposal"
      assert embed.description =~ "button below"
      refute embed.description =~ "[Submit trade]"
    end

    test "includes trade summary fields when provided" do
      fields = [%{name: "Receiving: T1", value: "• item", inline: false}]
      embed = ActionDmEmbed.build_submit_embed(["Bob"], fields)

      assert embed.fields == fields
    end

    test "multiple recipients uses generic line" do
      embed = ActionDmEmbed.build_submit_embed(["Bob", "Carol"], [])

      assert embed.description =~ "Recipients accepted your trade proposal"
      refute embed.description =~ "Bob accepted"
    end
  end

  describe "build_declined_embed/4" do
    test "creator sees decliner name and view instructions when URL set" do
      embed =
        ActionDmEmbed.build_declined_embed(
          "Pat",
          true,
          "https://example.com/view"
        )

      assert embed.title == "Trade Declined"
      assert embed.description =~ "Your trade proposal was declined by Pat"
      assert embed.description =~ "View trade"
      refute embed.description =~ "[View trade]"
    end

    test "non-creator copy" do
      embed = ActionDmEmbed.build_declined_embed("Pat", false, nil)

      assert embed.description =~ "A trade you were part of was declined by Pat"
      refute embed.description =~ "View trade"
    end

    test "nil declined_by becomes Someone" do
      embed = ActionDmEmbed.build_declined_embed(nil, true, nil)

      assert embed.description =~ "declined by Someone"
    end

    test "empty view_url omits link hint" do
      embed = ActionDmEmbed.build_declined_embed("Pat", true, "")

      refute embed.description =~ "View trade"
    end

    test "non-binary view_url omits link hint" do
      embed = ActionDmEmbed.build_declined_embed("Pat", false, :not_a_url)

      refute embed.description =~ "View trade"
    end

    test "no view URL omits footer and extra lookup copy" do
      embed = ActionDmEmbed.build_declined_embed("Pat", true, nil)

      refute Map.has_key?(embed, :footer)
      refute embed.description =~ "trade ID"
    end

    test "includes decline reason when provided" do
      embed =
        ActionDmEmbed.build_declined_embed("Pat", true, "https://ex/v",
          declined_reason: "  Not enough pitching depth  "
        )

      assert embed.description =~ "Decline reason"
      assert embed.description =~ "Not enough pitching depth"
    end
  end

  describe "with_settings_footer/2" do
    test "adds footer with URL" do
      embed = %{title: "Test"}

      result =
        ActionDmEmbed.with_settings_footer(
          embed,
          "https://trades.akosua.xyz/settings/notifications"
        )

      assert result.footer.text ==
               "Manage notifications: https://trades.akosua.xyz/settings/notifications"
    end

    test "skips for nil" do
      embed = %{title: "Test"}
      assert ActionDmEmbed.with_settings_footer(embed, nil) == embed
    end

    test "skips for empty string" do
      embed = %{title: "Test"}
      assert ActionDmEmbed.with_settings_footer(embed, "") == embed
    end
  end
end
