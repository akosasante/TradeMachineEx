defmodule TradeMachine.Jobs.EspnMlbPlayersSyncTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  alias TradeMachine.ESPN.Client
  alias TradeMachine.Jobs.EspnMlbPlayersSync
  alias TradeMachine.SyncLock

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, {:shared, self()})

    :ok
  end

  test "worker can be enqueued with correct queue" do
    {:ok, _} = Oban.insert(Oban.Production, EspnMlbPlayersSync.new(%{}))

    assert_enqueued(worker: EspnMlbPlayersSync, queue: :espn_sync)
  end

  test "worker has max_attempts set to 3" do
    assert EspnMlbPlayersSync.__opts__()[:max_attempts] == 3
  end

  test "worker uses espn_sync queue" do
    assert EspnMlbPlayersSync.__opts__()[:queue] == :espn_sync
  end

  test "worker has unique constraint configured" do
    unique_opts = EspnMlbPlayersSync.__opts__()[:unique]
    assert unique_opts[:period] == :infinity
    assert :executing in unique_opts[:states]
    assert :available in unique_opts[:states]
  end

  test "perform returns {:cancel, :already_running} when lock is held" do
    :acquired = SyncLock.acquire(:mlb_players_sync)

    try do
      result = EspnMlbPlayersSync.perform(%Oban.Job{id: 0, args: %{}})
      assert {:cancel, :already_running} = result
    after
      SyncLock.release(:mlb_players_sync)
    end
  end

  # ---------------------------------------------------------------------------
  # perform/1 — actual sync paths (with Req.Test stubs)
  # ---------------------------------------------------------------------------

  defp espn_player(id, full_name, opts \\ []) do
    pro_team_id = Keyword.get(opts, :pro_team_id, 1)

    %{
      "id" => id,
      "onTeamId" => 0,
      "status" => "FREEAGENT",
      "player" => %{
        "id" => id,
        "fullName" => full_name,
        "firstName" => full_name |> String.split() |> List.first(),
        "lastName" => full_name |> String.split() |> List.last(),
        "proTeamId" => pro_team_id,
        "defaultPositionId" => 6,
        "eligibleSlots" => [6],
        "active" => true
      }
    }
  end

  test "perform returns :ok when ESPN API returns an empty player set" do
    # Use an empty player list to avoid both Production and Staging repos
    # trying to insert the same rows into the same test schema, which would
    # cause a row-lock deadlock between the two sandbox transactions.
    Req.Test.stub(Client, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-fantasy-filter-player-count", "0")
      |> Req.Test.json(%{"players" => []})
    end)

    result = EspnMlbPlayersSync.perform(%Oban.Job{id: 10, args: %{}})

    assert result == :ok
  end

  test "perform returns {:error, reason} when ESPN API returns non-200" do
    Req.Test.stub(Client, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(503, ~s({"error": "service unavailable"}))
    end)

    result = EspnMlbPlayersSync.perform(%Oban.Job{id: 11, args: %{}})

    assert {:error, {:http_error, 503, _}} = result
  end

  test "perform returns {:error, reason} on network failure" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    result = EspnMlbPlayersSync.perform(%Oban.Job{id: 12, args: %{}})

    assert {:error, %Req.TransportError{}} = result
  end
end
