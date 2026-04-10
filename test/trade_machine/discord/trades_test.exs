defmodule TradeMachine.Discord.TradesTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.Trades

  describe "statuses_for_filter/1" do
    test "active" do
      assert Trades.statuses_for_filter("active") == [:requested, :pending, :accepted]
    end

    test "closed" do
      assert Trades.statuses_for_filter("closed") == [:rejected, :submitted]
    end

    test "all and nil map to no filter" do
      assert Trades.statuses_for_filter("all") == nil
      assert Trades.statuses_for_filter(nil) == nil
    end

    test "unknown values mean no filter" do
      assert Trades.statuses_for_filter("other") == nil
    end
  end
end
