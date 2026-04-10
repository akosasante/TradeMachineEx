defmodule TradeMachine.Discord.TradesTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Discord.Trades

  describe "statuses_for_filter/1" do
    test "returns active statuses" do
      assert Trades.statuses_for_filter("active") == [:requested, :pending, :accepted]
    end

    test "returns closed statuses" do
      assert Trades.statuses_for_filter("closed") == [:rejected, :submitted]
    end

    test "returns nil for 'all'" do
      assert Trades.statuses_for_filter("all") == nil
    end

    test "returns nil for nil" do
      assert Trades.statuses_for_filter(nil) == nil
    end

    test "returns nil for unknown filter" do
      assert Trades.statuses_for_filter("bogus") == nil
    end
  end
end
