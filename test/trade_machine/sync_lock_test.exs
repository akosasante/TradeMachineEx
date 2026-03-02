defmodule TradeMachine.SyncLockTest do
  use ExUnit.Case, async: false

  alias TradeMachine.SyncLock

  setup do
    SyncLock.force_release(:test_job)
    SyncLock.force_release(:job_a)
    SyncLock.force_release(:job_b)
    SyncLock.force_release(:mlb_players_sync)
    :ok
  end

  describe "acquire/1" do
    test "returns :acquired when lock is free" do
      assert :acquired = SyncLock.acquire(:test_job)
      SyncLock.release(:test_job)
    end

    test "returns {:already_running, _} when lock is held" do
      :acquired = SyncLock.acquire(:test_job)
      assert {:already_running, %DateTime{}} = SyncLock.acquire(:test_job)
      SyncLock.release(:test_job)
    end

    test "independent lock names do not interfere" do
      :acquired = SyncLock.acquire(:job_a)
      assert :acquired = SyncLock.acquire(:job_b)
      SyncLock.release(:job_a)
      SyncLock.release(:job_b)
    end
  end

  describe "release/1" do
    test "allows re-acquisition after release" do
      :acquired = SyncLock.acquire(:test_job)
      :ok = SyncLock.release(:test_job)
      assert :acquired = SyncLock.acquire(:test_job)
      SyncLock.release(:test_job)
    end

    test "no-ops when releasing an unheld lock" do
      assert :ok = SyncLock.release(:nonexistent)
    end

    test "ignores release from a different process" do
      :acquired = SyncLock.acquire(:test_job)

      Task.async(fn ->
        SyncLock.release(:test_job)
      end)
      |> Task.await()

      assert {:already_running, _} = SyncLock.acquire(:test_job)
      SyncLock.release(:test_job)
    end
  end

  describe "force_release/1" do
    test "releases lock regardless of holder" do
      :acquired = SyncLock.acquire(:test_job)

      Task.async(fn ->
        SyncLock.force_release(:test_job)
      end)
      |> Task.await()

      assert :acquired = SyncLock.acquire(:test_job)
      SyncLock.release(:test_job)
    end
  end

  describe "status/0" do
    test "returns empty map when no locks are held" do
      assert %{} = SyncLock.status()
    end

    test "returns held locks with pid and acquired_at" do
      :acquired = SyncLock.acquire(:test_job)
      status = SyncLock.status()

      assert %{test_job: %{pid: pid, acquired_at: %DateTime{}}} = status
      assert pid == self()
      SyncLock.release(:test_job)
    end
  end

  describe "auto-release on process death" do
    test "releases lock when the holder process exits" do
      task =
        Task.async(fn ->
          :acquired = SyncLock.acquire(:test_job)
          :holding
        end)

      :holding = Task.await(task)

      Process.sleep(50)

      assert :acquired = SyncLock.acquire(:test_job)
      SyncLock.release(:test_job)
    end

    test "releases lock when the holder process crashes" do
      {_pid, ref} =
        spawn_monitor(fn ->
          :acquired = SyncLock.acquire(:test_job)
          raise "boom"
        end)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      end

      Process.sleep(50)

      assert :acquired = SyncLock.acquire(:test_job)
      SyncLock.release(:test_job)
    end
  end
end
