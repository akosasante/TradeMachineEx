defmodule TradeMachine.Jobs.DraftPicksSyncTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.DraftPicks.SheetFetcher
  alias TradeMachine.Jobs.DraftPicksSync
  alias TradeMachine.SyncLock

  @minor_season 2025

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, {:shared, self()})

    original_thresholds = Application.get_env(:trade_machine, :draft_picks_season_thresholds)

    Application.put_env(:trade_machine, :draft_picks_season_thresholds, [
      {~D[2000-01-01], @minor_season}
    ])

    on_exit(fn ->
      Application.put_env(:trade_machine, :draft_picks_season_thresholds, original_thresholds)
    end)

    :ok
  end

  describe "worker configuration" do
    test "can be enqueued with correct queue" do
      {:ok, _} = Oban.insert(Oban.Production, DraftPicksSync.new(%{}))
      assert_enqueued(worker: DraftPicksSync, queue: :draft_sync)
    end

    test "has max_attempts set to 3" do
      assert DraftPicksSync.__opts__()[:max_attempts] == 3
    end

    test "uses draft_sync queue" do
      assert DraftPicksSync.__opts__()[:queue] == :draft_sync
    end

    test "has unique constraint configured" do
      unique_opts = DraftPicksSync.__opts__()[:unique]
      assert unique_opts[:period] == :infinity
      assert :executing in unique_opts[:states]
      assert :available in unique_opts[:states]
    end
  end

  describe "perform/1 - lock behaviour" do
    test "returns {:cancel, :already_running} when lock is held" do
      :acquired = SyncLock.acquire(:draft_picks_sync)

      try do
        result = DraftPicksSync.perform(%Oban.Job{id: 0, args: %{}})
        assert {:cancel, :already_running} = result
      after
        SyncLock.release(:draft_picks_sync)
      end
    end
  end

  describe "perform/1 - happy path" do
    test "returns :ok when sheet fetch and sync succeed (no picks in empty sheet)" do
      # An empty sheet (no parseable picks) is a valid successful run
      Req.Test.stub(SheetFetcher, fn conn ->
        Req.Test.json(conn, [])
      end)

      Application.put_env(:trade_machine, :draft_picks_sheet_id, "test-sheet-id")

      assert :ok = DraftPicksSync.perform(%Oban.Job{id: 1, args: %{}})
    after
      Application.delete_env(:trade_machine, :draft_picks_sheet_id)
    end
  end

  describe "perform/1 - error path" do
    test "returns {:error, reason} when SheetFetcher fails" do
      Req.Test.stub(SheetFetcher, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(403, ~s({"error": "forbidden"}))
      end)

      Application.put_env(:trade_machine, :draft_picks_sheet_id, "test-sheet-id")

      assert {:error, _reason} = DraftPicksSync.perform(%Oban.Job{id: 2, args: %{}})
    after
      Application.delete_env(:trade_machine, :draft_picks_sheet_id)
    end

    test "returns {:error, message} when execute_sync crashes" do
      # If the sheet_id env var is missing, fetch_from_config raises ArgumentError
      Application.delete_env(:trade_machine, :draft_picks_sheet_id)

      assert {:error, _reason} = DraftPicksSync.perform(%Oban.Job{id: 3, args: %{}})
    end
  end
end
