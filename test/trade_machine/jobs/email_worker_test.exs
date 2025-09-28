defmodule TradeMachine.Jobs.EmailWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: TradeMachine.Repo

  import Swoosh.TestAssertions

  alias TradeMachine.Data.User
  alias TradeMachine.Jobs.EmailWorker

  setup do
    # Enable Ecto.Adapters.SQL.Sandbox for database isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo)
  end

  describe "perform/1" do
    test "successfully processes reset_password email type" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id
      }

      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent using Swoosh TestAssertions
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end

    test "returns error for unknown email type" do
      user = insert_user()

      job_args = %{
        email_type: "unknown_email_type",
        data: user.id
      }

      assert {:error, :unknown_email_type} = perform_job(EmailWorker, job_args)

      # Assert no email was sent
      refute_email_sent()
    end

    test "handles user not found error for reset_password" do
      non_existent_user_id = Ecto.UUID.generate()

      job_args = %{
        email_type: "reset_password",
        data: non_existent_user_id
      }

      assert {:error, :user_not_found} = perform_job(EmailWorker, job_args)

      # Assert no email was sent
      refute_email_sent()
    end

    test "logs error for unknown email type" do
      user = insert_user()

      job_args = %{
        email_type: "invalid_type",
        data: user.id
      }

      # Capture logs to verify error logging
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          perform_job(EmailWorker, job_args)
        end)

      assert log_output =~ "Unknown email type: invalid_type"
    end
  end

  describe "Oban integration" do
    test "can be enqueued with valid args" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id
      }

      # Enqueue the job
      EmailWorker.new(job_args) |> Oban.insert!()

      # Assert job was enqueued with correct args
      assert_enqueued worker: EmailWorker, args: %{email_type: "reset_password", data: user.id}
    end

    test "uses correct queue and max_attempts" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id
      }

      # Check the job configuration directly without inserting
      job_changeset = EmailWorker.new(job_args)
      assert job_changeset.changes.queue == "emails"
      assert job_changeset.changes.max_attempts == 3

      # Also verify by enqueuing and checking with assert_enqueued
      EmailWorker.new(job_args) |> Oban.insert!()
      assert_enqueued queue: "emails", worker: EmailWorker
    end

    test "job processes successfully when enqueued and performed" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id
      }

      # Test the full flow: enqueue and perform
      EmailWorker.new(job_args) |> Oban.insert!()

      assert_enqueued worker: EmailWorker, args: job_args
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}]
      )
    end

    test "can handle multiple jobs in queue" do
      user1 = insert_user()
      user2 = insert_user(%{email: "user2@example.com", display_name: "User Two"})

      # Enqueue multiple jobs
      EmailWorker.new(%{email_type: "reset_password", data: user1.id}) |> Oban.insert!()
      EmailWorker.new(%{email_type: "reset_password", data: user2.id}) |> Oban.insert!()

      # Assert both jobs are enqueued
      enqueued_jobs = all_enqueued(worker: EmailWorker)
      assert length(enqueued_jobs) == 2

      # Perform both jobs
      assert :ok = perform_job(EmailWorker, %{email_type: "reset_password", data: user1.id})
      assert :ok = perform_job(EmailWorker, %{email_type: "reset_password", data: user2.id})

      # Assert both emails were sent
      assert_email_sent(to: [{"Test User", "test@example.com"}])
      assert_email_sent(to: [{"User Two", "user2@example.com"}])
    end
  end

  # Helper function to insert a test user into the database
  defp insert_user(attrs \\ %{}) do
    default_attrs = %{
      id: Ecto.UUID.generate(),
      display_name: "Test User",
      email: "test@example.com",
      password_reset_token: "sample-token-123",
      status: :active,
      role: :admin
    }

    attrs = Map.merge(default_attrs, attrs)

    user = struct(User, attrs)
    TradeMachine.Repo.insert!(user)
  end
end