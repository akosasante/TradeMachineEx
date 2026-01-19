#!/usr/bin/env elixir

# Test script for ESPN API Client
# Run with: mix run test_espn_client.exs

Mix.install([{:req, "~> 0.5"}, {:jason, "~> 1.3"}])

defmodule TestESPNClient do
  require Logger

  def run do
    Logger.configure(level: :info)

    # Load environment variables from .env if it exists
    load_env()

    espn_cookie = System.get_env("ESPN_COOKIE")
    espn_swid = System.get_env("ESPN_SWID")
    league_id = System.get_env("ESPN_LEAGUE_ID") || "545"

    if is_nil(espn_cookie) or is_nil(espn_swid) do
      IO.puts("""
      ERROR: ESPN credentials not found!

      Please create a .env file with:
      ESPN_COOKIE=your_espn_s2_cookie
      ESPN_SWID=your_swid
      ESPN_LEAGUE_ID=545
      """)

      System.halt(1)
    end

    IO.puts("\n=== Testing ESPN API Client ===\n")
    IO.puts("League ID: #{league_id}")
    IO.puts("Year: 2025\n")

    # Create client
    client = create_client(2025, espn_cookie, espn_swid, league_id)

    # Test 1: Get league members
    IO.puts("Test 1: Fetching league members...")

    case get_members(client) do
      {:ok, members} ->
        IO.puts("✓ Success! Found #{length(members)} members")
        IO.puts("  First member: #{inspect(List.first(members))}\n")

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}\n")
    end

    # Test 2: Get league teams
    IO.puts("Test 2: Fetching league teams...")

    case get_teams(client) do
      {:ok, teams} ->
        IO.puts("✓ Success! Found #{length(teams)} teams")

        IO.puts(
          "  First team: #{inspect(List.first(teams) |> Map.take(["id", "name", "abbrev"]))}\n"
        )

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}\n")
    end

    # Test 3: Get schedule (first few matchups)
    IO.puts("Test 3: Fetching schedule...")

    case get_schedule(client) do
      {:ok, schedule} ->
        IO.puts("✓ Success! Found #{length(schedule)} matchups")

        first_matchup = List.first(schedule)

        IO.puts(
          "  First matchup: ID=#{first_matchup["id"]}, Winner=#{first_matchup["winner"] || "UNDECIDED"}\n"
        )

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}\n")
    end

    # Test 4: Get roster for team 1
    IO.puts("Test 4: Fetching roster for team 1, scoring period 196...")

    case get_roster(client, 1, 196) do
      {:ok, roster} ->
        entries = roster["entries"] || []
        IO.puts("✓ Success! Found #{length(entries)} roster entries")

        if length(entries) > 0 do
          first_entry = List.first(entries)
          player_name = get_in(first_entry, ["playerPoolEntry", "player", "fullName"])
          IO.puts("  First player: #{player_name}\n")
        end

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}\n")
    end

    # Test 5: Get players (limited to first page)
    IO.puts("Test 5: Fetching first page of players...")

    case get_players_page(client, 0, 10) do
      {:ok, players} ->
        IO.puts("✓ Success! Found #{length(players)} players")

        if length(players) > 0 do
          first_player = List.first(players)
          player_name = get_in(first_player, ["player", "fullName"])
          IO.puts("  First player: #{player_name}\n")
        end

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}\n")
    end

    IO.puts("=== All tests completed ===")
  end

  defp create_client(year, cookie, swid, league_id) do
    base_url =
      "https://lm-api-reads.fantasy.espn.com/apis/v3/games/flb/seasons/#{year}/segments/0/leagues/#{league_id}"

    Req.new(
      base_url: base_url,
      headers: [{"cookie", "espn_s2=#{cookie}; SWID=#{swid};"}],
      receive_timeout: 30_000
    )
  end

  defp get_members(client) do
    case Req.get(client, url: "/members") do
      {:ok, %{status: 200, body: members}} -> {:ok, members}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_teams(client) do
    case Req.get(client, url: "/teams", params: [view: "mTeam"]) do
      {:ok, %{status: 200, body: teams}} -> {:ok, teams}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_schedule(client) do
    case Req.get(client, url: "/schedule", params: [view: "mScoreboard"]) do
      {:ok, %{status: 200, body: schedule}} -> {:ok, schedule}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_roster(client, team_id, scoring_period_id) do
    params = [forTeamId: team_id, scoringPeriodId: scoring_period_id, view: "mRoster"]

    case Req.get(client, url: "", params: params) do
      {:ok, %{status: 200, body: %{"teams" => [team | _]}}} -> {:ok, team["roster"]}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_players_page(client, offset, limit) do
    filter = %{
      players: %{
        limit: limit,
        offset: offset,
        sortPercOwned: %{sortAsc: false, sortPriority: 1}
      }
    }

    filter_json = Jason.encode!(filter)
    headers = [{"X-Fantasy-Filter", filter_json}]

    case Req.get(client, url: "", params: [view: "kona_player_info"], headers: headers) do
      {:ok, %{status: 200, body: %{"players" => players}}} -> {:ok, players}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_env do
    env_file = ".env"

    if File.exists?(env_file) do
      File.stream!(env_file)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(String.starts_with?(&1, "#") or &1 == ""))
      |> Enum.each(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> System.put_env(key, value)
          _ -> :ok
        end
      end)
    end
  end
end

TestESPNClient.run()
