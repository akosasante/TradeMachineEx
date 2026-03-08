defmodule TradeMachine.Jobs.DraftPicksSyncTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.Jobs.DraftPicksSync
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
    {:ok, _} = Oban.insert(Oban.Production, DraftPicksSync.new(%{}))
    assert_enqueued(worker: DraftPicksSync, queue: :draft_sync)
  end

  test "worker has max_attempts set to 3" do
    assert DraftPicksSync.__opts__()[:max_attempts] == 3
  end

  test "worker uses draft_sync queue" do
    assert DraftPicksSync.__opts__()[:queue] == :draft_sync
  end

  test "worker has unique constraint configured" do
    unique_opts = DraftPicksSync.__opts__()[:unique]
    assert unique_opts[:period] == :infinity
    assert :executing in unique_opts[:states]
    assert :available in unique_opts[:states]
  end

  test "perform returns {:cancel, :already_running} when lock is held" do
    :acquired = SyncLock.acquire(:draft_picks_sync)

    try do
      result = DraftPicksSync.perform(%Oban.Job{id: 0, args: %{}})
      assert {:cancel, :already_running} = result
    after
      SyncLock.release(:draft_picks_sync)
    end
  end
end
