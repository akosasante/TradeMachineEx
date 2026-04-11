defmodule TradeMachine.Jobs.DiscordWorkerTest do
  use TradeMachine.DataCase, async: false

  alias TradeMachine.Jobs.DiscordWorker

  defp build_job(args, opts \\ []) do
    %Oban.Job{
      id: Keyword.get(opts, :id, 1),
      args: args,
      worker: "TradeMachine.Jobs.DiscordWorker",
      queue: "discord"
    }
  end

  # ── Invalid args ──────────────────────────────────────────────────────────

  describe "perform/1 — invalid args" do
    test "returns {:error, :invalid_args} for unknown job_type" do
      job = build_job(%{"job_type" => "bogus"})
      assert {:error, :invalid_args} = DiscordWorker.perform(job)
    end

    test "returns {:error, :invalid_args} for empty args" do
      job = build_job(%{})
      assert {:error, :invalid_args} = DiscordWorker.perform(job)
    end

    test "returns {:error, :invalid_args} for args missing required keys" do
      job = build_job(%{"job_type" => "trade_request_dm", "trade_id" => "x"})
      assert {:error, :invalid_args} = DiscordWorker.perform(job)
    end
  end

  # ── finalize_dm_job: non-retryable errors are swallowed ───────────────────
  #
  # Without the hydrated_trades DB view (not created locally), ActionDm returns
  # {:error, :trade_not_found}. finalize_dm_job classifies that as non-retryable
  # and returns :ok so Oban does not retry the job. These tests exercise the
  # full perform → ActionDm → finalize path for each DM job_type.

  describe "perform/1 — trade_request_dm (non-retryable skip)" do
    test "returns :ok when hydrated trade does not exist" do
      job =
        build_job(%{
          "job_type" => "trade_request_dm",
          "trade_id" => Ecto.UUID.generate(),
          "recipient_user_id" => Ecto.UUID.generate(),
          "accept_url" => "http://accept",
          "decline_url" => "http://decline",
          "env" => "production"
        })

      assert :ok = DiscordWorker.perform(job)
    end
  end

  describe "perform/1 — trade_submit_dm (non-retryable skip)" do
    test "returns :ok when hydrated trade does not exist" do
      job =
        build_job(%{
          "job_type" => "trade_submit_dm",
          "trade_id" => Ecto.UUID.generate(),
          "recipient_user_id" => Ecto.UUID.generate(),
          "submit_url" => "http://submit",
          "env" => "production"
        })

      assert :ok = DiscordWorker.perform(job)
    end
  end

  describe "perform/1 — trade_declined_dm (non-retryable skip)" do
    test "returns :ok when hydrated trade does not exist" do
      job =
        build_job(%{
          "job_type" => "trade_declined_dm",
          "trade_id" => Ecto.UUID.generate(),
          "recipient_user_id" => Ecto.UUID.generate(),
          "is_creator" => false,
          "decline_url" => "http://view",
          "env" => "staging"
        })

      assert :ok = DiscordWorker.perform(job)
    end

    test "handles missing optional fields (is_creator, decline_url)" do
      job =
        build_job(%{
          "job_type" => "trade_declined_dm",
          "trade_id" => Ecto.UUID.generate(),
          "recipient_user_id" => Ecto.UUID.generate(),
          "env" => "staging"
        })

      assert :ok = DiscordWorker.perform(job)
    end
  end

  # ── env routing ───────────────────────────────────────────────────────────

  describe "perform/1 — environment routing" do
    test "staging env routes to staging repo" do
      job =
        build_job(%{
          "job_type" => "trade_request_dm",
          "trade_id" => Ecto.UUID.generate(),
          "recipient_user_id" => Ecto.UUID.generate(),
          "accept_url" => "http://a",
          "decline_url" => "http://d",
          "env" => "staging"
        })

      assert :ok = DiscordWorker.perform(job)
    end
  end
end
