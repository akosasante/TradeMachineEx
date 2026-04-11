defmodule TradeMachine.Discord.ClientDmTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.Client

  describe "send_dm_embed/3 — validation" do
    test "rejects non-numeric discord user id" do
      embed = %{title: "x", description: "y"}

      assert Client.send_dm_embed("not-a-snowflake", embed, []) ==
               {:error, :invalid_discord_user_id}
    end

    test "rejects user id with trailing junk after parse" do
      assert Client.send_dm_embed("12345abc", %{}, []) == {:error, :invalid_discord_user_id}
    end

    test "rejects empty string after trim" do
      assert Client.send_dm_embed("   ", %{}, []) == {:error, :invalid_discord_user_id}
    end
  end
end
