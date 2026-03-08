defmodule TradeMachine.ESPN.ClientTest do
  use ExUnit.Case, async: true

  alias TradeMachine.ESPN.Client
  alias TradeMachine.ESPN.Types

  # ---------------------------------------------------------------------------
  # new/2 — struct creation and URL routing
  # ---------------------------------------------------------------------------

  describe "new/2" do
    test "creates a client struct for 2024+ with correct base URL" do
      client = Client.new(2025, league_id: "545")

      assert %Client{year: 2025, league_id: "545"} = client
      assert client.req.options.base_url =~ "lm-api-reads.fantasy.espn.com"
      assert client.req.options.base_url =~ "2025"
    end

    test "creates a client struct for 2017-2023 with pre-2024 base URL" do
      client = Client.new(2023, league_id: "99")

      assert client.req.options.base_url =~ "fantasy.espn.com"
      assert client.req.options.base_url =~ "2023"
      refute client.req.options.base_url =~ "lm-api-reads"
    end

    test "creates a client for pre-2017 with leagueHistory URL" do
      client = Client.new(2016, league_id: "88")

      assert client.req.options.base_url =~ "leagueHistory"
      assert client.req.options.base_url =~ "2016"
    end

    test "defaults league_id to 545 when not provided" do
      client = Client.new(2025)

      assert client.league_id == "545"
    end
  end

  # ---------------------------------------------------------------------------
  # get_league_teams/2
  # ---------------------------------------------------------------------------

  describe "get_league_teams/2" do
    test "returns parsed FantasyTeam structs on 200" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, [%{"id" => 1, "abbrev" => "TST", "name" => "Test Team"}])
      end)

      client = Client.new(2025, league_id: "545")
      assert {:ok, [team]} = Client.get_league_teams(client)
      assert %Types.FantasyTeam{id: 1, abbrev: "TST", name: "Test Team"} = team
    end

    test "returns raw maps when raw: true" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, [%{"id" => 2, "abbrev" => "RAW", "name" => "Raw Team"}])
      end)

      client = Client.new(2025)
      assert {:ok, [raw]} = Client.get_league_teams(client, raw: true)
      assert raw["id"] == 2
      assert raw["abbrev"] == "RAW"
    end

    test "returns empty list when API returns empty list" do
      Req.Test.stub(Client, fn conn -> Req.Test.json(conn, []) end)

      client = Client.new(2025)
      assert {:ok, []} = Client.get_league_teams(client)
    end

    test "returns error tuple on non-200 HTTP status" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, ~s({"error": "unauthorized"}))
      end)

      client = Client.new(2025)
      assert {:error, {:http_error, 401, _}} = Client.get_league_teams(client)
    end

    test "returns error tuple on network failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      client = Client.new(2025)
      assert {:error, %Req.TransportError{reason: :timeout}} = Client.get_league_teams(client)
    end
  end

  # ---------------------------------------------------------------------------
  # get_league_members/2
  # ---------------------------------------------------------------------------

  describe "get_league_members/2" do
    test "returns parsed LeagueMember structs on 200" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, [
          %{
            "id" => "abc123",
            "displayName" => "Alice",
            "firstName" => "Alice",
            "lastName" => "Smith"
          }
        ])
      end)

      client = Client.new(2025)
      assert {:ok, [member]} = Client.get_league_members(client)
      assert %Types.LeagueMember{id: "abc123", display_name: "Alice"} = member
    end

    test "returns raw maps when raw: true" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, [%{"id" => "xyz", "displayName" => "Bob"}])
      end)

      client = Client.new(2025)
      assert {:ok, [raw]} = Client.get_league_members(client, raw: true)
      assert raw["id"] == "xyz"
    end

    test "returns error on non-200" do
      Req.Test.stub(Client, fn conn ->
        conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(403, "{}")
      end)

      client = Client.new(2025)
      assert {:error, {:http_error, 403, _}} = Client.get_league_members(client)
    end

    test "returns error on network failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      client = Client.new(2025)
      assert {:error, %Req.TransportError{}} = Client.get_league_members(client)
    end
  end

  # ---------------------------------------------------------------------------
  # get_schedule/2
  # ---------------------------------------------------------------------------

  describe "get_schedule/2" do
    test "returns parsed ScheduleMatchup structs on 200" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, [
          %{
            "id" => 1,
            "home" => %{"teamId" => 1, "totalPoints" => 100.0},
            "away" => %{"teamId" => 2, "totalPoints" => 90.0},
            "matchupPeriodId" => 1,
            "winner" => "HOME"
          }
        ])
      end)

      client = Client.new(2025)
      assert {:ok, [matchup]} = Client.get_schedule(client)
      assert %Types.ScheduleMatchup{id: 1} = matchup
    end

    test "returns raw maps when raw: true" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, [%{"id" => 7}])
      end)

      client = Client.new(2025)
      assert {:ok, [raw]} = Client.get_schedule(client, raw: true)
      assert raw["id"] == 7
    end

    test "returns error on non-200" do
      Req.Test.stub(Client, fn conn ->
        conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(500, "{}")
      end)

      client = Client.new(2025)
      assert {:error, {:http_error, 500, _}} = Client.get_schedule(client)
    end

    test "returns error on network failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      client = Client.new(2025)
      assert {:error, %Req.TransportError{}} = Client.get_schedule(client)
    end
  end

  # ---------------------------------------------------------------------------
  # get_roster/4
  # ---------------------------------------------------------------------------

  describe "get_roster/4" do
    test "returns parsed Roster struct when teams list has one entry" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{
          "teams" => [
            %{"roster" => %{"entries" => []}}
          ]
        })
      end)

      client = Client.new(2025)
      assert {:ok, %Types.Roster{}} = Client.get_roster(client, 1, 1)
    end

    test "returns raw roster map when raw: true" do
      roster_data = %{"entries" => [%{"playerId" => 42}]}

      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"teams" => [%{"roster" => roster_data}]})
      end)

      client = Client.new(2025)
      assert {:ok, ^roster_data} = Client.get_roster(client, 1, 1, raw: true)
    end

    test "returns unexpected_format error when teams list is empty" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"teams" => []})
      end)

      client = Client.new(2025)
      assert {:error, {:unexpected_format, _}} = Client.get_roster(client, 1, 1)
    end

    test "returns error on non-200" do
      Req.Test.stub(Client, fn conn ->
        conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(404, "{}")
      end)

      client = Client.new(2025)
      assert {:error, {:http_error, 404, _}} = Client.get_roster(client, 1, 1)
    end

    test "returns error on network failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      client = Client.new(2025)
      assert {:error, %Req.TransportError{}} = Client.get_roster(client, 1, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # get_all_players/2
  # ---------------------------------------------------------------------------

  describe "get_all_players/2" do
    test "returns all players when single page covers entire set" do
      player = %{"id" => 1, "player" => %{"id" => 1, "fullName" => "Test Player"}}

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-fantasy-filter-player-count", "1")
        |> Req.Test.json(%{"players" => [player]})
      end)

      client = Client.new(2025)
      assert {:ok, [entry]} = Client.get_all_players(client, raw: true, sleep_ms: 0)
      assert entry["id"] == 1
    end

    test "paginates when server total exceeds first page" do
      page1_player = %{"id" => 1, "player" => %{"id" => 1, "fullName" => "Player One"}}
      page2_player = %{"id" => 2, "player" => %{"id" => 2, "fullName" => "Player Two"}}

      call_count = :counters.new(1, [])

      Req.Test.stub(Client, fn conn ->
        n = :counters.get(call_count, 1) + 1
        :counters.put(call_count, 1, n)

        player = if n == 1, do: page1_player, else: page2_player

        conn
        |> Plug.Conn.put_resp_header("x-fantasy-filter-player-count", "2")
        |> Req.Test.json(%{"players" => [player]})
      end)

      client = Client.new(2025)

      assert {:ok, players} =
               Client.get_all_players(client, raw: true, limit: 1, sleep_ms: 0)

      assert length(players) == 2
      assert Enum.map(players, & &1["id"]) == [1, 2]
    end

    test "returns parsed PlayerPoolEntry structs when raw: false" do
      player = %{
        "id" => 100,
        "onTeamId" => 0,
        "status" => "FREEAGENT",
        "player" => %{"id" => 100, "fullName" => "Pool Player"}
      }

      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-fantasy-filter-player-count", "1")
        |> Req.Test.json(%{"players" => [player]})
      end)

      client = Client.new(2025)
      assert {:ok, [entry]} = Client.get_all_players(client, sleep_ms: 0)
      assert %Types.PlayerPoolEntry{id: 100} = entry
    end

    test "retries on 429 and succeeds on subsequent attempt" do
      player = %{"id" => 5, "player" => %{"id" => 5, "fullName" => "Retry Player"}}
      attempt = :counters.new(1, [])

      Req.Test.stub(Client, fn conn ->
        n = :counters.get(attempt, 1) + 1
        :counters.put(attempt, 1, n)

        if n == 1 do
          conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(429, "{}")
        else
          conn
          |> Plug.Conn.put_resp_header("x-fantasy-filter-player-count", "1")
          |> Req.Test.json(%{"players" => [player]})
        end
      end)

      client = Client.new(2025)

      assert {:ok, [entry]} =
               Client.get_all_players(client, raw: true, sleep_ms: 0, base_backoff_ms: 0)

      assert entry["id"] == 5
    end

    test "returns error after max 429 retries exhausted" do
      Req.Test.stub(Client, fn conn ->
        conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(429, "{}")
      end)

      client = Client.new(2025)

      assert {:error, {:http_error, 429, _}} =
               Client.get_all_players(client, sleep_ms: 0, base_backoff_ms: 0)
    end

    test "returns error on non-200 non-429 status" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(503, ~s({"error": "unavailable"}))
      end)

      client = Client.new(2025)
      assert {:error, {:http_error, 503, _}} = Client.get_all_players(client, sleep_ms: 0)
    end

    test "returns error on network failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      client = Client.new(2025)
      assert {:error, %Req.TransportError{reason: :timeout}} = Client.get_all_players(client)
    end
  end
end
