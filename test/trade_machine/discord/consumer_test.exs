defmodule TradeMachine.Discord.ConsumerTest do
  use ExUnit.Case, async: false

  alias TradeMachine.Discord.Consumer

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

  describe "handle_event/1" do
    test "READY registers slash commands when no guild ids are configured" do
      Application.delete_env(:trade_machine, :discord_staging_guild_ids)
      Application.delete_env(:trade_machine, :discord_production_guild_ids)

      assert Consumer.handle_event({:READY, %{application: %{id: 42}}, %{}}) == :ok
    end

    test "READY registers slash commands when staging guild ids are configured" do
      Application.put_env(:trade_machine, :discord_staging_guild_ids, [999_888_777_666_555_444])
      Application.delete_env(:trade_machine, :discord_production_guild_ids)

      assert Consumer.handle_event({:READY, %{application: %{id: 99}}, %{}}) == :ok
    end

    test "INTERACTION_CREATE dispatches through CommandRouter" do
      interaction = %{data: %{name: "not-a-real-command"}, token: "test-token", id: 1}

      assert Consumer.handle_event({:INTERACTION_CREATE, interaction, %{}}) == {:ok}
    end
  end
end
