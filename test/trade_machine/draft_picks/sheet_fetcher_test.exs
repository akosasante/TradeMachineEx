defmodule TradeMachine.DraftPicks.SheetFetcherTest do
  use ExUnit.Case, async: true

  alias TradeMachine.DraftPicks.SheetFetcher

  describe "fetch/2" do
    test "returns {:ok, rows} when response body is a list (auto-decoded CSV)" do
      rows = [["Round", "Owner", "", "OVR", "Current"], ["1", "Alice", "", "10", "Alice"]]

      Req.Test.stub(SheetFetcher, fn conn ->
        Req.Test.json(conn, rows)
      end)

      assert {:ok, ^rows} = SheetFetcher.fetch("sheet123", "gid456")
    end

    test "returns {:error, :unexpected_binary_body} when body is a binary string" do
      Req.Test.stub(SheetFetcher, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.resp(200, "Round,Owner\n1,Alice\n")
      end)

      assert {:error, :unexpected_binary_body} = SheetFetcher.fetch("sheet123", "gid456")
    end

    test "returns {:error, {:http_status, status}} on non-200 response" do
      Req.Test.stub(SheetFetcher, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(403, ~s({"error": "forbidden"}))
      end)

      assert {:error, {:http_status, 403}} = SheetFetcher.fetch("sheet123", "gid456")
    end

    test "returns {:error, reason} on network failure" do
      Req.Test.stub(SheetFetcher, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               SheetFetcher.fetch("sheet123", "gid456")
    end
  end

  describe "fetch_from_config/0" do
    test "delegates to fetch/2 using application config values" do
      Application.put_env(:trade_machine, :draft_picks_sheet_id, "config_sheet_id")
      Application.put_env(:trade_machine, :draft_picks_sheet_gid, "config_gid")

      rows = [["Round", "Owner", "", "OVR"], ["1", "Alice", "", "10"]]

      Req.Test.stub(SheetFetcher, fn conn ->
        Req.Test.json(conn, rows)
      end)

      assert {:ok, ^rows} = SheetFetcher.fetch_from_config()
    after
      Application.delete_env(:trade_machine, :draft_picks_sheet_id)
      Application.delete_env(:trade_machine, :draft_picks_sheet_gid)
    end

    test "uses default GID of 142978697 when not configured" do
      Application.put_env(:trade_machine, :draft_picks_sheet_id, "sheet_id")
      Application.delete_env(:trade_machine, :draft_picks_sheet_gid)

      rows = [["Round", "Owner"]]

      Req.Test.stub(SheetFetcher, fn conn ->
        assert conn.query_string =~ "gid=142978697"
        Req.Test.json(conn, rows)
      end)

      assert {:ok, ^rows} = SheetFetcher.fetch_from_config()
    after
      Application.delete_env(:trade_machine, :draft_picks_sheet_id)
    end
  end
end
