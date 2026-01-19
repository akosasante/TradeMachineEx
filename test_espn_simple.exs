#!/usr/bin/env elixir

# Simple ESPN API test - run with: elixir test_espn_simple.exs
# No Mix required, just Elixir

IO.puts("\n=== Simple ESPN API Test ===\n")

# Check for required env vars
espn_cookie = System.get_env("ESPN_COOKIE")
espn_swid = System.get_env("ESPN_SWID")
league_id = System.get_env("ESPN_LEAGUE_ID") || "545"

if is_nil(espn_cookie) or is_nil(espn_swid) do
  IO.puts("""
  ERROR: ESPN credentials not found!

  Run with environment variables:
  ESPN_COOKIE=xxx ESPN_SWID=yyy elixir test_espn_simple.exs

  Or source your .env file first:
  source .env && elixir test_espn_simple.exs
  """)

  System.halt(1)
end

IO.puts("✓ Found ESPN credentials")
IO.puts("  League ID: #{league_id}")
IO.puts("  Cookie length: #{String.length(espn_cookie)} chars")
IO.puts("  SWID length: #{String.length(espn_swid)} chars")
IO.puts("\nCredentials are set. To test the actual API, use the full test:")
IO.puts("  source .env && mix run --no-start test_espn_client.exs")
IO.puts("\nOr run within IEx:")
IO.puts("  source .env && iex -S mix")
IO.puts("  client = TradeMachine.ESPN.Client.new(2025)")
IO.puts("  TradeMachine.ESPN.Client.get_league_members(client)")
