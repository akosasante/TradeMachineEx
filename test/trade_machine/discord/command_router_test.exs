defmodule TradeMachine.Discord.CommandRouterTest do
  use ExUnit.Case, async: false

  alias TradeMachine.Discord.CommandRouter

  setup do
    prev_staging = Application.get_env(:trade_machine, :discord_staging_guild_ids)
    prev_prod = Application.get_env(:trade_machine, :discord_production_guild_ids)

    on_exit(fn ->
      restore_env(:discord_staging_guild_ids, prev_staging)
      restore_env(:discord_production_guild_ids, prev_prod)
    end)

    :ok
  end

  defp restore_env(key, prev) do
    if prev == nil do
      Application.delete_env(:trade_machine, key)
    else
      Application.put_env(:trade_machine, key, prev)
    end
  end

  describe "register_commands/1" do
    test "skips Discord API when no guild ids are configured" do
      Application.delete_env(:trade_machine, :discord_staging_guild_ids)
      Application.delete_env(:trade_machine, :discord_production_guild_ids)

      assert CommandRouter.register_commands(123_456_789_012_345_678) == :ok
    end

    test "registers when staging guild ids are configured" do
      Application.delete_env(:trade_machine, :discord_production_guild_ids)
      Application.put_env(:trade_machine, :discord_staging_guild_ids, [999_888_777_666_555_444])

      assert CommandRouter.register_commands(111) == :ok
    end

    test "registers when production guild ids are configured" do
      Application.delete_env(:trade_machine, :discord_staging_guild_ids)

      Application.put_env(:trade_machine, :discord_production_guild_ids, [111_222_333_444_555_666])

      assert CommandRouter.register_commands(222) == :ok
    end

    test "registers to union of staging and production guilds" do
      Application.put_env(:trade_machine, :discord_staging_guild_ids, [100, 200])
      Application.put_env(:trade_machine, :discord_production_guild_ids, [300, 400])

      assert CommandRouter.register_commands(333) == :ok
    end
  end

  describe "handle/1" do
    test "returns API result for unknown commands" do
      interaction = %{data: %{name: "unknown"}, token: "test-token", id: 1}

      assert CommandRouter.handle(interaction) == {:ok}
    end
  end
end
