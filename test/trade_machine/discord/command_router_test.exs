defmodule TradeMachine.Discord.CommandRouterTest do
  use ExUnit.Case, async: false

  alias TradeMachine.Discord.CommandRouter

  setup do
    prev_guild = Application.get_env(:trade_machine, :discord_guild_id)

    on_exit(fn ->
      if prev_guild == nil do
        Application.delete_env(:trade_machine, :discord_guild_id)
      else
        Application.put_env(:trade_machine, :discord_guild_id, prev_guild)
      end
    end)

    :ok
  end

  describe "register_commands/1" do
    test "skips Discord API when DISCORD_GUILD_ID is unset" do
      Application.delete_env(:trade_machine, :discord_guild_id)

      assert CommandRouter.register_commands(123_456_789_012_345_678) == :ok
    end

    test "parses string guild id and completes (API may fail in test)" do
      Application.put_env(:trade_machine, :discord_guild_id, "999888777666555444")

      assert CommandRouter.register_commands(111) == :ok
    end

    test "registers when guild id is an integer" do
      Application.put_env(:trade_machine, :discord_guild_id, 999_888_777_666_555_444)

      assert CommandRouter.register_commands(222) == :ok
    end
  end

  describe "handle/1" do
    test "returns API result for unknown commands" do
      interaction = %{data: %{name: "unknown"}, token: "test-token", id: 1}

      assert CommandRouter.handle(interaction) == {:ok}
    end
  end
end
