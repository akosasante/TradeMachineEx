defmodule TradeMachine.Jobs.EmailWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  import Swoosh.TestAssertions

  alias TradeMachine.Data.User
  alias TradeMachine.Jobs.EmailWorker
  alias TradeMachine.Mailer

  setup do
    # Enable Ecto.Adapters.SQL.Sandbox for database isolation - checkout both repos
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    # Set search_path to test schema for sandbox connections
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    # IMPORTANT: For async tests, we need to allow both repos to share the same sandbox
    # This allows Staging repo to see data inserted by Production repo
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, {:shared, self()})

    # Allow cross-repo visibility by sharing the sandbox between repos
    Ecto.Adapters.SQL.Sandbox.allow(TradeMachine.Repo.Production, self(), self())
    Ecto.Adapters.SQL.Sandbox.allow(TradeMachine.Repo.Staging, self(), self())

    :ok
  end

  describe "perform/1" do
    test "successfully processes reset_password email type" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id,
        env: "production"
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
        data: user.id,
        env: "production"
      }

      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent using Swoosh TestAssertions (to staging email)
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
        data: user.id,
        env: "production"
      }

      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent using Swoosh TestAssertions (to staging email)
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
        data: user.id,
        env: "production"
      }

      assert {:error, :unknown_email_type} = perform_job(EmailWorker, job_args)

      # Assert no email was sent
      refute_email_sent()
    end

    test "handles user not found error for reset_password" do
      non_existent_user_id = Ecto.UUID.generate()

      job_args = %{
        email_type: "reset_password",
        data: non_existent_user_id,
        env: "production"
      }

      assert {:error, :user_not_found} = perform_job(EmailWorker, job_args)

      # Assert no email was sent
      refute_email_sent()
    end

    test "handles user not found error for registration email" do
      non_existent_user_id = Ecto.UUID.generate()

      job_args = %{
        email_type: "registration",
        data: non_existent_user_id,
        env: "production"
      }

      assert {:error, :user_not_found} = perform_job(EmailWorker, job_args)
      refute_email_sent()
    end

    test "handles user not found error for test email" do
      non_existent_user_id = Ecto.UUID.generate()

      job_args = %{
        email_type: "test",
        data: non_existent_user_id,
        env: "production"
      }

      assert {:error, :user_not_found} = perform_job(EmailWorker, job_args)
      refute_email_sent()
    end

    test "uses staging repo when env is not production" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id,
        env: "staging"
      }

      # Staging repo is checked out in setup; user was inserted in production repo so
      # the staging repo won't find them, returning user_not_found
      assert {:error, :user_not_found} = perform_job(EmailWorker, job_args)
    end

    test "returns error for invalid job args missing required fields" do
      job_args = %{bad_field: "value"}
      assert {:error, :invalid_args} = perform_job(EmailWorker, job_args)
    end

    test "logs error for unknown email type" do
      user = insert_user()

      job_args = %{
        email_type: "invalid_type",
        data: user.id,
        env: "production"
      }

      # Capture logs to verify error logging
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          perform_job(EmailWorker, job_args)
        end)

      assert log_output =~ "Unknown email type: invalid_type"
    end
  end

  describe "Mailer default repo" do
    test "send_password_reset_email/2 uses default repo when no repo arg given" do
      result = Mailer.send_password_reset_email(Ecto.UUID.generate(), "production")
      assert result == {:error, :user_not_found}
    end
  end

  describe "Oban integration" do
    test "worker configuration is correct" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id,
        env: "production"
      }

      # Check the job configuration directly
      job_changeset = EmailWorker.new(job_args)
      assert job_changeset.changes.queue == "emails"
      assert job_changeset.changes.max_attempts == 3
      assert job_changeset.changes.worker == "TradeMachine.Jobs.EmailWorker"
    end

    test "job processes successfully when performed" do
      user = insert_user()

      job_args = %{
        email_type: "reset_password",
        data: user.id,
        env: "production"
      }

      # Test job execution using perform_job (doesn't require running Oban)
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent (to staging email)
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}]
      )
    end

    test "can handle multiple jobs" do
      user1 = insert_user()
      user2 = insert_user(%{email: "user2@example.com", display_name: "User Two"})

      # Perform both jobs
      assert :ok =
               perform_job(EmailWorker, %{
                 email_type: "reset_password",
                 data: user1.id,
                 env: "production"
               })

      assert :ok =
               perform_job(EmailWorker, %{
                 email_type: "reset_password",
                 data: user2.id,
                 env: "production"
               })

      # Assert both emails were sent
      assert_email_sent(to: [{"Test User", "test@example.com"}])
      assert_email_sent(to: [{"User Two", "user2@example.com"}])
    end

    test "can handle registration and test email jobs" do
      user = insert_user()

      # Perform both jobs
      assert :ok =
               perform_job(EmailWorker, %{
                 email_type: "registration",
                 data: user.id,
                 env: "production"
               })

      assert :ok =
               perform_job(EmailWorker, %{email_type: "test", data: user.id, env: "production"})

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
        "env" => "production",
        "trace_context" => %{
          "traceparent" => "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
          "tracestate" => "grafana=sessionId:abc123"
        }
      }

      # Test that the job completes successfully with trace context
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent (tracing should not interfere with core functionality, to staging email)
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}]
      )
    end

    test "processes email without trace context successfully" do
      user = insert_user()

      job_args = %{
        "email_type" => "reset_password",
        "data" => user.id,
        "env" => "production"
      }

      # Test that the job completes successfully without trace context
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent (should work normally without tracing, to staging email)
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
        "env" => "production",
        "trace_context" => %{
          "traceparent" => "invalid-format"
        }
      }

      # Test that the job completes successfully even with invalid trace context
      assert :ok = perform_job(EmailWorker, job_args)

      # Assert email was sent (invalid tracing should not break email functionality, to staging email)
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
        "env" => "production",
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
        "env" => "production",
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
        "data" => user.id,
        "env" => "production"
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
        "env" => "production",
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
        "env" => "production",
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
    TradeMachine.Repo.Production.insert!(user)
  end
end
