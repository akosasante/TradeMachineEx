defmodule TradeMachine.Discord.ConsumerTest do
  use ExUnit.Case, async: false

  alias TradeMachine.Discord.Consumer

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

  describe "handle_event/1" do
    test "READY registers slash commands when guild id is unset" do
      Application.delete_env(:trade_machine, :discord_guild_id)

      assert Consumer.handle_event({:READY, %{application: %{id: 42}}, %{}}) == :ok
    end

    test "READY registers slash commands when guild id is configured" do
      Application.put_env(:trade_machine, :discord_guild_id, 999_888_777_666_555_444)

      assert Consumer.handle_event({:READY, %{application: %{id: 99}}, %{}}) == :ok
    end

    test "INTERACTION_CREATE dispatches through CommandRouter" do
      interaction = %{data: %{name: "not-a-real-command"}, token: "test-token", id: 1}

      assert Consumer.handle_event({:INTERACTION_CREATE, interaction, %{}}) == {:ok}
    end
  end
end
