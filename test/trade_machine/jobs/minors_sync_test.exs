defmodule TradeMachine.Jobs.MinorsSyncTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.Jobs.MinorsSync
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

  describe "Oban worker configuration" do
    test "uses minors_sync queue" do
      assert MinorsSync.__opts__()[:queue] == :minors_sync
    end

    test "has max_attempts set to 5" do
      assert MinorsSync.__opts__()[:max_attempts] == 5
    end

    test "has unique constraint configured with infinity period" do
      unique_opts = MinorsSync.__opts__()[:unique]
      assert unique_opts[:period] == :infinity
      assert :executing in unique_opts[:states]
      assert :available in unique_opts[:states]
      assert :retryable in unique_opts[:states]
    end

    test "can be enqueued with correct queue" do
      {:ok, _} = Oban.insert(Oban.Production, MinorsSync.new(%{}))
      assert_enqueued(worker: MinorsSync, queue: :minors_sync)
    end
  end

  describe "perform/1 - lock guard" do
    test "returns {:cancel, :already_running} when lock is held" do
      :acquired = SyncLock.acquire(:minors_sync)

      try do
        result = MinorsSync.perform(%Oban.Job{id: 0, args: %{}})
        assert {:cancel, :already_running} = result
      after
        SyncLock.release(:minors_sync)
      end
    end
  end
end
