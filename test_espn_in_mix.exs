# Test script for ESPN API Client (runs within Mix project)
# Run with: source .env && mix run test_espn_in_mix.exs

require Logger

# Start necessary applications for HTTP requests
Application.ensure_all_started(:req)
Application.ensure_all_started(:finch)

# Start Finch supervisor for Req
Finch.start_link(name: Req.Finch)

IO.puts("\n=== Testing ESPN API Client ===\n")

# Check environment variables
espn_cookie = System.get_env("ESPN_COOKIE")
espn_swid = System.get_env("ESPN_SWID")
league_id = System.get_env("ESPN_LEAGUE_ID") || "545"

if is_nil(espn_cookie) or is_nil(espn_swid) do
  IO.puts("""
  ERROR: ESPN credentials not found!

  Please ensure your .env file has:
  ESPN_COOKIE=your_espn_s2_cookie
  ESPN_SWID=your_swid
  ESPN_LEAGUE_ID=545

  Then run: source .env && mix run --no-start test_espn_in_mix.exs
  """)

  System.halt(1)
end

IO.puts("✓ ESPN credentials loaded")
IO.puts("  League ID: #{league_id}")
IO.puts("  Year: 2025\n")

# Create client
IO.puts("Creating ESPN client...")
client = TradeMachine.ESPN.Client.new(2025)
IO.puts("✓ Client created\n")

# Test 1: Get league members
IO.puts("Test 1: Fetching league members...")

case TradeMachine.ESPN.Client.get_league_members(client) do
  {:ok, members} ->
    IO.puts("✓ Success! Found #{length(members)} members")

    if length(members) > 0 do
      first = List.first(members)
      IO.puts("  First member: #{first["displayName"]} (ID: #{first["id"]})")
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 2: Get league teams
IO.puts("Test 2: Fetching league teams...")

case TradeMachine.ESPN.Client.get_league_teams(client) do
  {:ok, teams} ->
    IO.puts("✓ Success! Found #{length(teams)} teams")

    if length(teams) > 0 do
      first = List.first(teams)
      IO.puts("  First team: #{first["name"] || first["location"]} (ID: #{first["id"]})")
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 3: Get schedule
IO.puts("Test 3: Fetching schedule...")

case TradeMachine.ESPN.Client.get_schedule(client) do
  {:ok, schedule} ->
    IO.puts("✓ Success! Found #{length(schedule)} matchups")

    if length(schedule) > 0 do
      first = List.first(schedule)
      winner = first["winner"] || "UNDECIDED"
      IO.puts("  First matchup: ID=#{first["id"]}, Winner=#{winner}")
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 4: Get roster for team 1
IO.puts("Test 4: Fetching roster for team 1, scoring period 196...")

case TradeMachine.ESPN.Client.get_roster(client, 1, 196) do
  {:ok, roster} ->
    entries = roster["entries"] || []
    IO.puts("✓ Success! Found #{length(entries)} roster entries")

    if length(entries) > 0 do
      first_entry = List.first(entries)
      player_name = get_in(first_entry, ["playerPoolEntry", "player", "fullName"])
      IO.puts("  First player: #{player_name}")
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 5: Get first page of players (limited to avoid long wait)
IO.puts("Test 5: Fetching first 10 players...")

# Manually fetch just one page for testing
filter = %{
  players: %{
    limit: 10,
    offset: 0,
    sortPercOwned: %{sortAsc: false, sortPriority: 1}
  }
}

filter_json = Jason.encode!(filter)
headers = [{"X-Fantasy-Filter", filter_json}]

case Req.get(client.req, url: "", params: [view: "kona_player_info"], headers: headers) do
  {:ok, %{status: 200, body: %{"players" => players}}} ->
    IO.puts("✓ Success! Found #{length(players)} players")

    if length(players) > 0 do
      first = List.first(players)
      player_name = get_in(first, ["player", "fullName"])
      IO.puts("  First player: #{player_name}")
    end

    IO.puts("")

  {:ok, %{status: status}} ->
    IO.puts("✗ Failed with HTTP status: #{status}\n")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

IO.puts("=== All tests completed ===")
IO.puts("\nTo test the full pagination for players, run:")
IO.puts("  {:ok, all_players} = TradeMachine.ESPN.Client.get_all_players(client)")
