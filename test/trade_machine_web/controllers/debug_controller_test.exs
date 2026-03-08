defmodule TradeMachineWeb.DebugControllerTest do
  use TradeMachineWeb.ConnCase, async: false

  describe "GET /debug/trace" do
    test "returns 200 with span info", %{conn: conn} do
      conn = get(conn, "/debug/trace")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["status"] == "test_span_created"
      assert is_binary(body["result"])
      assert is_binary(body["message"])
    end
  end

  describe "GET /debug/distributed-trace" do
    test "returns 400 when traceparent header is missing", %{conn: conn} do
      conn = get(conn, "/debug/distributed-trace")

      assert conn.status == 400
      body = json_response(conn, 400)
      assert body["error"] == "traceparent header required"
      assert is_binary(body["usage"])
    end

    test "returns 200 and runs distributed trace when valid traceparent provided", %{conn: conn} do
      traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      conn =
        conn
        |> put_req_header("traceparent", traceparent)
        |> get("/debug/distributed-trace")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["status"] == "distributed_test_completed"
      assert body["traceparent"] == traceparent
      assert is_binary(body["result"])
    end
  end
end
