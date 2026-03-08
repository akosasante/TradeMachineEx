defmodule TradeMachine.Jobs.EspnTeamSyncTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.ESPN.Client
  alias TradeMachine.Jobs.EspnTeamSync

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, {:shared, self()})

    :ok
  end

  # ---------------------------------------------------------------------------
  # Worker configuration
  # ---------------------------------------------------------------------------

  test "worker uses espn_sync queue" do
    assert EspnTeamSync.__opts__()[:queue] == :espn_sync
  end

  test "worker has max_attempts set to 3" do
    assert EspnTeamSync.__opts__()[:max_attempts] == 3
  end

  test "worker can be enqueued" do
    {:ok, _} = Oban.insert(Oban.Production, EspnTeamSync.new(%{}))

    assert_enqueued(worker: EspnTeamSync, queue: :espn_sync)
  end

  # ---------------------------------------------------------------------------
  # perform/1 — happy path
  # ---------------------------------------------------------------------------

  test "perform returns :ok when ESPN API returns teams (no matching DB teams)" do
    # Return two teams from the API. No matching teams in the test DB so all
    # will be skipped, but the sync itself should succeed with :ok.
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, [
        %{"id" => 1, "abbrev" => "TST", "name" => "Test Team One"},
        %{"id" => 2, "abbrev" => "TST2", "name" => "Test Team Two"}
      ])
    end)

    result = EspnTeamSync.perform(%Oban.Job{id: 1, args: %{}})

    assert result == :ok
  end

  # ---------------------------------------------------------------------------
  # perform/1 — API error path
  # ---------------------------------------------------------------------------

  test "perform returns {:error, reason} when ESPN API call fails" do
    Req.Test.stub(Client, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(500, ~s({"error": "internal server error"}))
    end)

    result = EspnTeamSync.perform(%Oban.Job{id: 2, args: %{}})

    assert {:error, {:http_error, 500, _}} = result
  end

  test "perform returns {:error, reason} on network failure" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    result = EspnTeamSync.perform(%Oban.Job{id: 3, args: %{}})

    assert {:error, %Req.TransportError{}} = result
  end
end
