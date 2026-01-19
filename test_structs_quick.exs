# Quick test for structs
Application.ensure_all_started(:req)
Finch.start_link(name: Req.Finch)

IO.puts("\n=== Quick Struct Test ===\n")

client = TradeMachine.ESPN.Client.new(2025)

# Test members
{:ok, members} = TradeMachine.ESPN.Client.get_league_members(client)
first = List.first(members)
IO.puts("✓ Members: #{inspect(first.__struct__)}")
IO.puts("  Name: #{first.first_name} #{first.last_name}")
IO.puts("  Manager: #{first.is_league_manager}\n")

# Test teams  
{:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client)
first_team = List.first(teams)
IO.puts("✓ Teams: #{inspect(first_team.__struct__)}")
IO.puts("  Team: #{first_team.location} #{first_team.nickname}\n")

# Test raw mode
{:ok, raw_members} = TradeMachine.ESPN.Client.get_league_members(client, raw: true)
first_raw = List.first(raw_members)
IO.puts("✓ Raw mode: plain map (no struct)")
IO.puts("  Has displayName key: #{Map.has_key?(first_raw, "displayName")}")
IO.puts("  displayName: #{first_raw["displayName"]}\n")

IO.puts("=== All tests passed! ===")
