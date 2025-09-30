defmodule TradeMachine.Jobs.EmailWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: TradeMachine.Repo

  import Swoosh.TestAssertions

  alias TradeMachine.Data.User
  alias TradeMachine.Jobs.EmailWorker
  alias TradeMachine.Tracing.TraceContext

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

    test "successfully processes registration email type" do
      user = insert_user()

      job_args = %{
        email_type: "registration",
        data: user.id
      }

      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent using Swoosh TestAssertions
      assert_email_sent(
        subject: "You have been invited to register on FFF Trade Machine",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end

    test "successfully processes test email type" do
      user = insert_user()

      job_args = %{
        email_type: "test",
        data: user.id
      }

      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent using Swoosh TestAssertions
      assert_email_sent(
        subject: "Test email from Flex Fox Fantasy League TradeMachine",
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
      assert_enqueued(worker: EmailWorker, args: %{email_type: "reset_password", data: user.id})
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
      assert_enqueued(queue: "emails", worker: EmailWorker)
    end

    test "job processes successfully when enqueued and performed" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id
      }

      # Test the full flow: enqueue and perform
      EmailWorker.new(job_args) |> Oban.insert!()

      assert_enqueued(worker: EmailWorker, args: job_args)
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

    test "can handle registration and test email jobs" do
      user = insert_user()

      # Enqueue registration and test email jobs
      EmailWorker.new(%{email_type: "registration", data: user.id}) |> Oban.insert!()
      EmailWorker.new(%{email_type: "test", data: user.id}) |> Oban.insert!()

      # Assert both jobs are enqueued
      enqueued_jobs = all_enqueued(worker: EmailWorker)
      assert length(enqueued_jobs) == 2

      # Perform both jobs
      assert :ok = perform_job(EmailWorker, %{email_type: "registration", data: user.id})
      assert :ok = perform_job(EmailWorker, %{email_type: "test", data: user.id})

      # Assert both emails were sent
      assert_email_sent(subject: "You have been invited to register on FFF Trade Machine")
      assert_email_sent(subject: "Test email from Flex Fox Fantasy League TradeMachine")
    end
  end

  describe "distributed tracing integration" do
    test "processes email with trace context successfully" do
      user = insert_user()

      job_args = %{
        "email_type" => "reset_password",
        "data" => user.id,
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
          "tracestate" => "grafana=sessionId:abc123"
        }
      }

      # Test that the job completes successfully with trace context
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent (tracing should not interfere with core functionality)
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}]
      )
    end

    test "processes email without trace context successfully" do
      user = insert_user()

      job_args = %{
        "email_type" => "reset_password",
        "data" => user.id
      }

      # Test that the job completes successfully without trace context
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent (should work normally without tracing)
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}]
      )
    end

    test "handles invalid trace context gracefully" do
      user = insert_user()

      job_args = %{
        "email_type" => "reset_password",
        "data" => user.id,
        "trace_context" => %{
          "traceparent" => "invalid-format"
        }
      }

      # Test that the job completes successfully even with invalid trace context
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent (invalid tracing should not break email functionality)
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}]
      )
    end

    test "trace context extraction does not interfere with error handling" do
      non_existent_user_id = Ecto.UUID.generate()

      job_args = %{
        "email_type" => "reset_password",
        "data" => non_existent_user_id,
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        }
      }

      # Test that error handling still works correctly with trace context
      assert {:error, :user_not_found} = perform_job(EmailWorker, job_args)

      # Assert no email was sent
      refute_email_sent()
    end

    test "logs trace context information when present" do
      user = insert_user()

      job_args = %{
        "email_type" => "reset_password",
        "data" => user.id,
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        }
      }

      # Capture logs to verify trace context logging
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          perform_job(EmailWorker, job_args)
        end)

      # Should log that trace context was extracted
      assert log_output =~ "Extracted trace context"
      assert log_output =~ "4bf92f3577b34da6a3ce929d0e0e4736"
    end

    test "logs when no trace context is found" do
      user = insert_user()

      job_args = %{
        "email_type" => "reset_password",
        "data" => user.id
      }

      # Capture logs to verify no trace context logging
      log_output =
        ExUnit.CaptureLog.capture_log([level: :debug], fn ->
          perform_job(EmailWorker, job_args)
        end)

      # Should log that no trace context was found
      assert log_output =~ "No trace context found in job args"
    end

    test "handles registration email with trace context" do
      user = insert_user()

      job_args = %{
        "email_type" => "registration",
        "data" => user.id,
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        }
      }

      assert :ok = perform_job(EmailWorker, job_args)

      assert_email_sent(subject: "You have been invited to register on FFF Trade Machine")
    end

    test "handles test email with trace context" do
      user = insert_user()

      job_args = %{
        "email_type" => "test",
        "data" => user.id,
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        }
      }

      assert :ok = perform_job(EmailWorker, job_args)

      assert_email_sent(subject: "Test email from Flex Fox Fantasy League TradeMachine")
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
