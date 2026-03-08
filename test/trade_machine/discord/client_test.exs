defmodule TradeMachine.Discord.ClientTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.Client

  describe "channel_id/1" do
    test "returns nil when environment variable is not set" do
      System.delete_env("DISCORD_CHANNEL_ID_PRODUCTION")
      assert Client.channel_id(:production) == nil
    end

    test "returns nil for empty string" do
      System.put_env("DISCORD_CHANNEL_ID_STAGING", "")
      assert Client.channel_id(:staging) == nil
      System.delete_env("DISCORD_CHANNEL_ID_STAGING")
    end

    test "returns integer channel ID from environment" do
      System.put_env("DISCORD_CHANNEL_ID_STAGING", "993941280184864928")
      assert Client.channel_id(:staging) == 993_941_280_184_864_928
      System.delete_env("DISCORD_CHANNEL_ID_STAGING")
    end

    test "reads from correct env var for production" do
      System.put_env("DISCORD_CHANNEL_ID_PRODUCTION", "123456789")
      assert Client.channel_id(:production) == 123_456_789
      System.delete_env("DISCORD_CHANNEL_ID_PRODUCTION")
    end
  end

  describe "send_trade_announcement/2" do
    test "returns error when channel is not configured" do
      System.delete_env("DISCORD_CHANNEL_ID_PRODUCTION")
      embed = %{title: "Test", description: "Test embed"}

      assert {:error, :channel_not_configured} =
               Client.send_trade_announcement(embed, :production)
    end
  end
end
