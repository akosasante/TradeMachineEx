defmodule TradeMachineTest do
  use ExUnit.Case, async: true

  describe "ping/0" do
    test "returns pong" do
      assert TradeMachine.ping() == "pong"
    end
  end
end
