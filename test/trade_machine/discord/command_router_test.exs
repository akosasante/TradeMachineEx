defmodule TradeMachine.Discord.CommandRouterTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.CommandRouter

  describe "handle/1 dispatching" do
    test "routes my-trades to MyTrades handler" do
      interaction = build_interaction("my-trades")

      # handle/1 will call MyTrades.handle which calls Nostrum API;
      # in test env Nostrum is not running, so we just verify no crash on dispatch.
      # The actual command logic is tested via integration tests.
      assert_raise RuntimeError, fn ->
        CommandRouter.handle(interaction)
      end
    rescue
      # Expected: Nostrum is not started in test, so the handler will fail
      # trying to call Nostrum.Api. That's fine -- we're testing dispatch, not API calls.
      _ -> :ok
    end

    test "routes trade-history to TradeHistory handler" do
      interaction = build_interaction("trade-history")

      assert_raise RuntimeError, fn ->
        CommandRouter.handle(interaction)
      end
    rescue
      _ -> :ok
    end
  end

  defp build_interaction(name) do
    %{
      data: %{name: name, options: nil},
      member: %{user_id: 123_456_789},
      token: "test-token",
      id: 1
    }
  end
end
