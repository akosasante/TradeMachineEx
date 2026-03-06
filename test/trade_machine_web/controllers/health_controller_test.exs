defmodule TradeMachineWeb.HealthControllerTest do
  use TradeMachineWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 when database is reachable", %{conn: conn} do
      conn = get(conn, "/health")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["healthy"] == true
      assert body["service"] == "trade_machine_ex"
      assert is_binary(body["version"])
      assert is_binary(body["timestamp"])
    end

    test "response includes database check result", %{conn: conn} do
      conn = get(conn, "/health")

      body = json_response(conn, 200)
      assert %{"healthy" => true, "message" => message} = body["checks"]["database"]
      assert message =~ "successful"
    end

    test "response includes oban check result with correct shape", %{conn: conn} do
      conn = get(conn, "/health")

      # In test env, Oban queues are not running (queues: false), so oban.healthy
      # will be false — but this should NOT affect the HTTP status (database drives that).
      body = json_response(conn, 200)
      assert %{"healthy" => _, "message" => _} = body["checks"]["oban"]
    end

    test "oban status does not affect HTTP status when database is healthy", %{conn: conn} do
      # In test env Oban queues are disabled, so oban check will report unhealthy.
      # The endpoint should still return 200 since only the database check determines status.
      conn = get(conn, "/health")

      body = json_response(conn, 200)
      assert conn.status == 200
      assert body["healthy"] == true
      assert body["checks"]["oban"]["healthy"] == false
    end
  end

  describe "GET /ready" do
    test "returns 200 when database is reachable", %{conn: conn} do
      conn = get(conn, "/ready")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["status"] == "ready"
      assert is_binary(body["timestamp"])
    end
  end

  describe "GET /live" do
    test "always returns 200", %{conn: conn} do
      conn = get(conn, "/live")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["status"] == "alive"
      assert is_binary(body["timestamp"])
    end
  end
end
