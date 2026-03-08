defmodule TradeMachine.Jobs.EspnTeamSyncTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.Jobs.EspnTeamSync

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, {:shared, self()})

    :ok
  end

  describe "Oban worker configuration" do
    test "uses espn_sync queue" do
      assert EspnTeamSync.__opts__()[:queue] == :espn_sync
    end

    test "has max_attempts set to 3" do
      assert EspnTeamSync.__opts__()[:max_attempts] == 3
    end

    test "can be enqueued with correct queue" do
      {:ok, _} = Oban.insert(Oban.Production, EspnTeamSync.new(%{}))
      assert_enqueued(worker: EspnTeamSync, queue: :espn_sync)
    end
  end
end
