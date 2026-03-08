defmodule TradeMachine.ESPN.SearchTest do
  use ExUnit.Case, async: true

  alias TradeMachine.ESPN.Search

  defp player_hit(uid, name, opts \\ []) do
    %{
      "uid" => uid,
      "displayName" => name,
      "sport" => Keyword.get(opts, :sport, "baseball"),
      "subtitle" => Keyword.get(opts, :subtitle, "Some Team"),
      "description" => Keyword.get(opts, :description, "Outfielder"),
      "defaultLeagueSlug" => Keyword.get(opts, :league_slug, "mlb"),
      "image" => %{"default" => "https://example.com/img.png"}
    }
  end

  defp player_section(hits) do
    %{
      "results" => [
        %{
          "type" => "player",
          "contents" => hits
        }
      ]
    }
  end

  # ---------------------------------------------------------------------------
  # search_mlb_player/2
  # ---------------------------------------------------------------------------

  describe "search_mlb_player/2" do
    test "returns parsed results for baseball players on 200" do
      uid = "s:1~l:10~a:4567"

      Req.Test.stub(Search, fn conn ->
        Req.Test.json(conn, player_section([player_hit(uid, "Mike Trout")]))
      end)

      assert {:ok, [result]} = Search.search_mlb_player("Mike Trout")
      assert result.espn_id == 4567
      assert result.name == "Mike Trout"
      assert result.uid == uid
      assert result.image_url == "https://example.com/img.png"
    end

    test "filters out non-baseball sport results" do
      Req.Test.stub(Search, fn conn ->
        Req.Test.json(
          conn,
          player_section([
            player_hit("s:1~a:1", "Baseball Player"),
            player_hit("s:2~a:2", "Football Player", sport: "football")
          ])
        )
      end)

      assert {:ok, results} = Search.search_mlb_player("Player")
      assert length(results) == 1
      assert hd(results).name == "Baseball Player"
    end

    test "returns empty list when no player section in results" do
      Req.Test.stub(Search, fn conn ->
        Req.Test.json(conn, %{"results" => []})
      end)

      assert {:ok, []} = Search.search_mlb_player("Nobody")
    end

    test "returns empty list when body is not a map" do
      Req.Test.stub(Search, fn conn ->
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = Search.search_mlb_player("Nobody")
    end

    test "extracts nil espn_id when uid does not match pattern" do
      Req.Test.stub(Search, fn conn ->
        Req.Test.json(conn, player_section([player_hit("bad-uid-format", "Player X")]))
      end)

      assert {:ok, [result]} = Search.search_mlb_player("Player X")
      assert result.espn_id == nil
    end

    test "extracts nil espn_id when uid is nil" do
      hit = %{
        "uid" => nil,
        "displayName" => "No UID Player",
        "sport" => "baseball",
        "subtitle" => nil,
        "description" => nil,
        "defaultLeagueSlug" => nil,
        "image" => nil
      }

      Req.Test.stub(Search, fn conn ->
        Req.Test.json(conn, player_section([hit]))
      end)

      assert {:ok, [result]} = Search.search_mlb_player("No UID Player")
      assert result.espn_id == nil
      assert result.image_url == nil
    end

    test "returns :rate_limited on 429" do
      Req.Test.stub(Search, fn conn ->
        conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(429, "{}")
      end)

      assert {:error, :rate_limited} = Search.search_mlb_player("Test")
    end

    test "returns http_error tuple on non-200 non-429 status" do
      Req.Test.stub(Search, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, ~s({"error": "server error"}))
      end)

      assert {:error, {:http_error, 500, _}} = Search.search_mlb_player("Test")
    end

    test "returns error on network failure" do
      Req.Test.stub(Search, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %Req.TransportError{reason: :timeout}} = Search.search_mlb_player("Test")
    end
  end
end
