# Test ESPN client with Ecto structs
# Run with: export $(grep -v '^#' .env | xargs) && mix run --no-start test_espn_structs.exs

Application.ensure_all_started(:logger)
Application.ensure_all_started(:jason)
Application.ensure_all_started(:req)
Finch.start_link(name: Req.Finch)

alias TradeMachine.ESPN.Types

IO.puts("\n=== Testing ESPN Client with Ecto Structs ===\n")

client = TradeMachine.ESPN.Client.new(2025)

# Test 1: Get members as structs
IO.puts("Test 1: Fetching members as structs...")

case TradeMachine.ESPN.Client.get_league_members(client) do
  {:ok, members} ->
    IO.puts("✓ Success! Found #{length(members)} members")
    first = List.first(members)
    IO.puts("  Type: #{inspect(first.__struct__)}")
    IO.puts("  First member: #{first.first_name} #{first.last_name} (@#{first.display_name})")
    IO.puts("  Is manager: #{first.is_league_manager}")
    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 2: Get teams as structs
IO.puts("Test 2: Fetching teams as structs...")

case TradeMachine.ESPN.Client.get_league_teams(client) do
  {:ok, teams} ->
    IO.puts("✓ Success! Found #{length(teams)} teams")
    first = List.first(teams)
    IO.puts("  Type: #{inspect(first.__struct__)}")
    IO.puts("  First team: #{first.location} #{first.nickname} (ID: #{first.id})")

    if first.record && first.record.overall do
      IO.puts("  Record: #{first.record.overall.wins}W-#{first.record.overall.losses}L")
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 3: Get schedule as structs
IO.puts("Test 3: Fetching schedule as structs...")

case TradeMachine.ESPN.Client.get_schedule(client) do
  {:ok, schedule} ->
    IO.puts("✓ Success! Found #{length(schedule)} matchups")
    first = List.first(schedule)
    IO.puts("  Type: #{inspect(first.__struct__)}")
    IO.puts("  First matchup ID: #{first.id}")
    IO.puts("  Winner: #{first.winner || "UNDECIDED"}")

    if first.home do
      IO.puts("  Home team: #{first.home.team_id}")
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 4: Get roster as struct
IO.puts("Test 4: Fetching roster as struct...")

case TradeMachine.ESPN.Client.get_roster(client, 1, 196) do
  {:ok, roster} ->
    IO.puts("✓ Success! Found #{length(roster.entries)} roster entries")
    IO.puts("  Type: #{inspect(roster.__struct__)}")

    if length(roster.entries) > 0 do
      first_entry = List.first(roster.entries)
      IO.puts("  Entry type: #{inspect(first_entry.__struct__)}")

      if first_entry.player_pool_entry && first_entry.player_pool_entry.player do
        player = first_entry.player_pool_entry.player
        IO.puts("  First player: #{player.full_name}")
        IO.puts("  Player type: #{inspect(player.__struct__)}")
      end
    end

    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 5: Get first 10 players as structs
IO.puts("Test 5: Fetching first 10 players as structs...")

case TradeMachine.ESPN.Client.get_all_players(client, limit: 10, sleep_ms: 0) do
  {:ok, players} ->
    IO.puts("✓ Success! Found #{length(players)} players")
    first = List.first(players)
    IO.puts("  Type: #{inspect(first.__struct__)}")
    IO.puts("  First player: #{first.player.full_name}")
    IO.puts("  Player type: #{inspect(first.player.__struct__)}")
    IO.puts("")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}\n")
end

# Test 6: Compare raw vs struct
IO.puts("Test 6: Comparing raw vs struct responses...")

case TradeMachine.ESPN.Client.get_league_members(client, raw: true) do
  {:ok, raw_members} ->
    first_raw = List.first(raw_members)
    IO.puts("✓ Raw response type: #{inspect(first_raw.__struct__)}")
    IO.puts("  Keys: #{inspect(Map.keys(first_raw) |> Enum.take(5))}")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}")
end

case TradeMachine.ESPN.Client.get_league_members(client) do
  {:ok, struct_members} ->
    first_struct = List.first(struct_members)
    IO.puts("✓ Struct response type: #{inspect(first_struct.__struct__)}")
    IO.puts("  Fields: #{inspect(Map.keys(first_struct) |> Enum.take(5))}")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}")
end

IO.puts("\n=== All tests completed ===")
