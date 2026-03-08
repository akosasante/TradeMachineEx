defmodule TradeMachine.SyncTrackingTest do
  use ExUnit.Case, async: false

  alias TradeMachine.Data.SyncJobExecution
  alias TradeMachine.SyncTracking

  @repo TradeMachine.Repo.Production

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(@repo)
    TestHelper.set_search_path_for_sandbox(@repo)
    :ok
  end

  describe "start_sync/3" do
    test "creates a SyncJobExecution record with :started status" do
      {:ok, execution} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)

      assert execution.job_type == :minors_sync
      assert execution.database_scope == :production
      assert execution.status == :started
      assert %DateTime{} = execution.started_at
      assert execution.id != nil
    end

    test "accepts all valid job types" do
      for job_type <- [:espn_team_sync, :mlb_players_sync, :draft_picks_sync] do
        {:ok, execution} = SyncTracking.start_sync(job_type, :production, repo: @repo)
        assert execution.job_type == job_type
      end
    end

    test "accepts all valid database scopes" do
      for scope <- [:production, :staging, :both] do
        {:ok, execution} = SyncTracking.start_sync(:minors_sync, scope, repo: @repo)
        assert execution.database_scope == scope
      end
    end

    test "stores optional oban_job_id and trace_id" do
      {:ok, execution} =
        SyncTracking.start_sync(:minors_sync, :production,
          repo: @repo,
          oban_job_id: 42,
          trace_id: "abc123"
        )

      assert execution.oban_job_id == 42
      assert execution.trace_id == "abc123"
    end

    test "stores optional metadata" do
      {:ok, execution} =
        SyncTracking.start_sync(:minors_sync, :both,
          repo: @repo,
          metadata: %{"sheet_id" => "abc", "gid" => "123"}
        )

      assert execution.metadata["sheet_id"] == "abc"
      assert execution.metadata["gid"] == "123"
    end
  end

  describe "complete_sync/3" do
    test "updates status to :completed with duration and metrics" do
      {:ok, execution} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)
      Process.sleep(5)

      {:ok, completed} =
        SyncTracking.complete_sync(
          execution,
          %{records_processed: 100, records_updated: 80, records_skipped: 20},
          repo: @repo
        )

      assert completed.status == :completed
      assert %DateTime{} = completed.completed_at
      assert completed.duration_ms >= 0
      assert completed.records_processed == 100
      assert completed.records_updated == 80
      assert completed.records_skipped == 20
    end

    test "completes with no metrics map" do
      {:ok, execution} = SyncTracking.start_sync(:espn_team_sync, :production, repo: @repo)

      {:ok, completed} = SyncTracking.complete_sync(execution, %{}, repo: @repo)

      assert completed.status == :completed
      assert completed.records_processed == nil
    end

    test "merges metadata from initial start and completion" do
      {:ok, execution} =
        SyncTracking.start_sync(:minors_sync, :both,
          repo: @repo,
          metadata: %{"sheet_id" => "abc"}
        )

      {:ok, completed} =
        SyncTracking.complete_sync(
          execution,
          %{metadata: %{"rows_fetched" => 500}},
          repo: @repo
        )

      assert completed.metadata["sheet_id"] == "abc"
      assert completed.metadata["rows_fetched"] == 500
    end

    test "handles nil existing metadata when completing with new metadata" do
      {:ok, execution} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)

      {:ok, completed} =
        SyncTracking.complete_sync(
          execution,
          %{metadata: %{"production" => %{"matched" => 5}}},
          repo: @repo
        )

      assert completed.metadata["production"]["matched"] == 5
    end

    test "preserves existing metadata when completing without new metadata" do
      {:ok, execution} =
        SyncTracking.start_sync(:minors_sync, :production,
          repo: @repo,
          metadata: %{"sheet_id" => "existing"}
        )

      {:ok, completed} =
        SyncTracking.complete_sync(
          execution,
          %{records_processed: 10},
          repo: @repo
        )

      assert completed.metadata["sheet_id"] == "existing"
    end
  end

  describe "fail_sync/3" do
    test "updates status to :failed with error message and duration" do
      {:ok, execution} = SyncTracking.start_sync(:minors_sync, :staging, repo: @repo)
      Process.sleep(5)

      {:ok, failed} = SyncTracking.fail_sync(execution, "HTTP request timed out", repo: @repo)

      assert failed.status == :failed
      assert failed.error_message == "HTTP request timed out"
      assert %DateTime{} = failed.completed_at
      assert failed.duration_ms >= 0
    end
  end

  describe "get_last_sync/3" do
    test "returns the most recent completed sync for the given type and scope" do
      {:ok, execution} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)
      {:ok, _} = SyncTracking.complete_sync(execution, %{}, repo: @repo)

      result = SyncTracking.get_last_sync(:minors_sync, :production, repo: @repo)

      assert result != nil
      assert result.job_type == :minors_sync
      assert result.database_scope == :production
      assert result.status == :completed
    end

    test "returns nil when no completed sync exists" do
      {:ok, execution} = SyncTracking.start_sync(:draft_picks_sync, :staging, repo: @repo)
      {:ok, _} = SyncTracking.fail_sync(execution, "error", repo: @repo)

      result = SyncTracking.get_last_sync(:draft_picks_sync, :staging, repo: @repo)
      assert result == nil
    end

    test "returns nil when no syncs exist for the type" do
      result = SyncTracking.get_last_sync(:draft_picks_sync, :production, repo: @repo)
      assert result == nil
    end
  end

  describe "get_sync_history/3" do
    test "returns completed and failed syncs within the time window" do
      {:ok, e1} = SyncTracking.start_sync(:espn_team_sync, :production, repo: @repo)
      {:ok, _} = SyncTracking.complete_sync(e1, %{}, repo: @repo)

      {:ok, e2} = SyncTracking.start_sync(:espn_team_sync, :production, repo: @repo)
      {:ok, _} = SyncTracking.fail_sync(e2, "error", repo: @repo)

      history = SyncTracking.get_sync_history(:espn_team_sync, :production, repo: @repo)

      assert length(history) == 2
      assert Enum.all?(history, &(&1.job_type == :espn_team_sync))
    end

    test "returns history for all scopes when database_scope is nil" do
      {:ok, e1} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)
      {:ok, _} = SyncTracking.complete_sync(e1, %{}, repo: @repo)

      {:ok, e2} = SyncTracking.start_sync(:minors_sync, :staging, repo: @repo)
      {:ok, _} = SyncTracking.complete_sync(e2, %{}, repo: @repo)

      history = SyncTracking.get_sync_history(:minors_sync, nil, repo: @repo)
      assert length(history) == 2
    end

    test "returns empty list when no history exists" do
      history = SyncTracking.get_sync_history(:draft_picks_sync, :production, repo: @repo)
      assert history == []
    end

    test "respects the limit option" do
      for _ <- 1..5 do
        {:ok, e} = SyncTracking.start_sync(:mlb_players_sync, :production, repo: @repo)
        {:ok, _} = SyncTracking.complete_sync(e, %{}, repo: @repo)
      end

      history =
        SyncTracking.get_sync_history(:mlb_players_sync, :production, repo: @repo, limit: 3)

      assert length(history) == 3
    end
  end

  describe "get_recent_failures/1" do
    test "returns failed syncs within the default 24-hour window" do
      {:ok, e1} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)
      {:ok, _} = SyncTracking.fail_sync(e1, "connection refused", repo: @repo)

      {:ok, e2} = SyncTracking.start_sync(:espn_team_sync, :staging, repo: @repo)
      {:ok, _} = SyncTracking.complete_sync(e2, %{}, repo: @repo)

      failures = SyncTracking.get_recent_failures(repo: @repo)

      assert length(failures) >= 1
      assert Enum.all?(failures, &(&1.status == :failed))
    end

    test "returns empty list when there are no recent failures" do
      {:ok, e} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)
      {:ok, _} = SyncTracking.complete_sync(e, %{}, repo: @repo)

      failures = SyncTracking.get_recent_failures(repo: @repo, hours: 0)
      assert failures == []
    end

    test "accepts custom hours option" do
      {:ok, e} = SyncTracking.start_sync(:minors_sync, :production, repo: @repo)
      {:ok, _} = SyncTracking.fail_sync(e, "timeout", repo: @repo)

      failures = SyncTracking.get_recent_failures(repo: @repo, hours: 1)
      assert length(failures) >= 1
    end

    test "can be called with no arguments (uses default repo)" do
      # Exercises the default-arg head clause
      failures = SyncTracking.get_recent_failures()
      assert is_list(failures)
    end
  end

  describe "full lifecycle" do
    test "records a complete start → complete cycle and can query it" do
      {:ok, execution} =
        SyncTracking.start_sync(:espn_team_sync, :both,
          repo: @repo,
          oban_job_id: 7,
          trace_id: "trace-xyz"
        )

      assert execution.status == :started
      assert is_nil(execution.completed_at)
      assert is_nil(execution.duration_ms)

      {:ok, completed} =
        SyncTracking.complete_sync(
          execution,
          %{records_processed: 12, records_updated: 10},
          repo: @repo
        )

      assert completed.status == :completed
      assert completed.records_processed == 12

      persisted = @repo.get!(SyncJobExecution, completed.id)
      assert persisted.status == :completed
      assert persisted.records_processed == 12
    end
  end
end
