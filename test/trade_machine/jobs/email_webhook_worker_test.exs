defmodule TradeMachine.Jobs.EmailWebhookWorkerTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.Data.Email
  alias TradeMachine.Jobs.EmailWebhookWorker
  alias TradeMachine.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)
    :ok
  end

  describe "Oban worker configuration" do
    test "has correct queue and max_attempts" do
      job_changeset = EmailWebhookWorker.new(%{"message_id" => "test", "event" => "delivered"})
      assert job_changeset.changes.queue == "emails"
      assert job_changeset.changes.max_attempts == 3
      assert job_changeset.changes.worker == "TradeMachine.Jobs.EmailWebhookWorker"
    end
  end

  describe "perform/1 — creates new email record" do
    test "inserts a new email record when message_id does not exist" do
      message_id = "new-message-#{System.unique_integer()}"

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "delivered",
                 "env" => "production"
               })

      assert %Email{status: "delivered"} =
               Repo.Production.get(Email, message_id)
    end

    test "inserts record in staging repo when env is staging" do
      message_id = "stg-message-#{System.unique_integer()}"

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "delivered",
                 "env" => "staging"
               })

      assert %Email{status: "delivered"} =
               Repo.Staging.get(Email, message_id)

      assert is_nil(Repo.Production.get(Email, message_id))
    end
  end

  describe "perform/1 — upserts existing email record" do
    test "updates status when an email record with the same message_id already exists" do
      message_id = "existing-message-#{System.unique_integer()}"

      Repo.Production.insert!(%Email{message_id: message_id, status: "sent"})

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "delivered",
                 "env" => "production"
               })

      assert %Email{status: "delivered"} =
               Repo.Production.get(Email, message_id)
    end

    test "handles multiple status updates for the same message_id" do
      message_id = "multi-update-#{System.unique_integer()}"

      Repo.Production.insert!(%Email{message_id: message_id, status: "sent"})

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "delivered",
                 "env" => "production"
               })

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "opened",
                 "env" => "production"
               })

      assert %Email{status: "opened"} =
               Repo.Production.get(Email, message_id)
    end
  end

  describe "perform/1 — env / repo selection" do
    test "defaults to production repo when env key is absent" do
      message_id = "no-env-message-#{System.unique_integer()}"

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "delivered"
               })

      assert %Email{} = Repo.Production.get(Email, message_id)
      assert is_nil(Repo.Staging.get(Email, message_id))
    end

    test "defaults to production repo for unknown env values" do
      message_id = "unknown-env-#{System.unique_integer()}"

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "bounced",
                 "env" => "development"
               })

      assert %Email{} = Repo.Production.get(Email, message_id)
    end
  end

  describe "perform/1 — optional fields" do
    test "handles optional email and reason fields gracefully" do
      message_id = "optional-fields-#{System.unique_integer()}"

      assert :ok =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => message_id,
                 "event" => "bounced",
                 "env" => "production",
                 "email" => "user@example.com",
                 "reason" => "mailbox full"
               })

      assert %Email{status: "bounced"} =
               Repo.Production.get(Email, message_id)
    end
  end

  describe "perform/1 — error handling" do
    test "returns error tuple and logs when the upsert fails" do
      # A nil status violates the DB not-null constraint, triggering the error branch
      assert {:error, %Ecto.Changeset{}} =
               perform_job(EmailWebhookWorker, %{
                 "message_id" => "error-case-#{System.unique_integer()}",
                 "event" => nil,
                 "env" => "production"
               })
    end
  end
end
