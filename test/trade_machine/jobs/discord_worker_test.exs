defmodule TradeMachine.Jobs.DiscordWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.Jobs.DiscordWorker

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    :ok
  end

  describe "worker configuration" do
    test "uses the :discord queue" do
      job_changeset =
        DiscordWorker.new(%{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate(),
          env: "production"
        })

      assert job_changeset.changes.queue == "discord"
    end

    test "has max_attempts of 3" do
      job_changeset =
        DiscordWorker.new(%{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate(),
          env: "production"
        })

      assert job_changeset.changes.max_attempts == 3
    end

    test "uses the correct worker name" do
      job_changeset =
        DiscordWorker.new(%{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate(),
          env: "production"
        })

      assert job_changeset.changes.worker == "TradeMachine.Jobs.DiscordWorker"
    end
  end

  describe "perform/1 argument handling" do
    test "returns error for invalid args (missing job_type)" do
      result =
        perform_job(DiscordWorker, %{
          data: Ecto.UUID.generate(),
          env: "production"
        })

      assert {:error, :invalid_args} = result
    end

    test "returns error for invalid args (missing data)" do
      result =
        perform_job(DiscordWorker, %{
          job_type: "trade_announcement",
          env: "production"
        })

      assert {:error, :invalid_args} = result
    end

    test "returns error for invalid args (missing env)" do
      result =
        perform_job(DiscordWorker, %{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate()
        })

      assert {:error, :invalid_args} = result
    end

    test "returns error for completely empty args" do
      assert {:error, :invalid_args} = perform_job(DiscordWorker, %{})
    end

    test "returns error for invalid trade ID (not a valid UUID)" do
      result =
        perform_job(DiscordWorker, %{
          job_type: "trade_announcement",
          data: "not-a-uuid",
          env: "staging"
        })

      assert {:error, :invalid_trade_id} = result
    end

    test "returns error for non-existent trade (valid UUID but not in DB)" do
      result =
        perform_job(DiscordWorker, %{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate(),
          env: "staging"
        })

      assert {:error, :trade_not_found} = result
    end
  end

  describe "environment selection" do
    test "production env maps to :production (returns trade_not_found, not env error)" do
      result =
        perform_job(DiscordWorker, %{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate(),
          env: "production"
        })

      assert {:error, :trade_not_found} = result
    end

    test "staging env maps to :staging (returns trade_not_found, not env error)" do
      result =
        perform_job(DiscordWorker, %{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate(),
          env: "staging"
        })

      assert {:error, :trade_not_found} = result
    end

    test "development env falls back to :staging (returns trade_not_found, not env error)" do
      result =
        perform_job(DiscordWorker, %{
          job_type: "trade_announcement",
          data: Ecto.UUID.generate(),
          env: "development"
        })

      assert {:error, :trade_not_found} = result
    end
  end
end
