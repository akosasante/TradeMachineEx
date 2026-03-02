defmodule TradeMachine.Jobs.EspnMlbPlayersSyncTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.Jobs.EspnMlbPlayersSync
  alias TradeMachine.SyncLock

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, {:shared, self()})

    :ok
  end

  test "worker can be enqueued with correct queue" do
    {:ok, _} = Oban.insert(Oban.Production, EspnMlbPlayersSync.new(%{}))

    assert_enqueued(worker: EspnMlbPlayersSync, queue: :espn_sync)
  end

  test "worker has max_attempts set to 3" do
    assert EspnMlbPlayersSync.__opts__()[:max_attempts] == 3
  end

  test "worker uses espn_sync queue" do
    assert EspnMlbPlayersSync.__opts__()[:queue] == :espn_sync
  end

  test "worker has unique constraint configured" do
    unique_opts = EspnMlbPlayersSync.__opts__()[:unique]
    assert unique_opts[:period] == :infinity
    assert :executing in unique_opts[:states]
    assert :available in unique_opts[:states]
  end

  test "perform returns {:cancel, :already_running} when lock is held" do
    :acquired = SyncLock.acquire(:mlb_players_sync)

    try do
      result = EspnMlbPlayersSync.perform(%Oban.Job{id: 0, args: %{}})
      assert {:cancel, :already_running} = result
    after
      SyncLock.release(:mlb_players_sync)
    end
  end
end
