# ESPN Fantasy API Client

This module provides a Req-based HTTP client for interacting with the ESPN Fantasy Baseball API.

## Setup

### 1. Environment Variables

Create a `.env` file in the TradeMachineEx root directory (this file is gitignored):

```bash
ESPN_COOKIE=your_espn_s2_cookie_value_here
ESPN_SWID=your_espn_swid_value_here
ESPN_LEAGUE_ID=545
```

To get your ESPN cookies:
1. Log into ESPN Fantasy Baseball in your browser
2. Open browser DevTools (F12)
3. Go to Application/Storage → Cookies → fantasy.espn.com
4. Copy the values for `espn_s2` and `SWID`

### 2. Configuration

The client reads credentials from Application config (configured in `config/runtime.exs`):

```elixir
config :trade_machine,
  espn_cookie: System.get_env("ESPN_COOKIE"),
  espn_swid: System.get_env("ESPN_SWID"),
  espn_league_id: System.get_env("ESPN_LEAGUE_ID") || "545"
```

## Usage

### Initialize Client

Create a client instance with the season year:

```elixir
# Create client for 2025 season
client = TradeMachine.ESPN.Client.new(2025)

# Override league ID if needed
client = TradeMachine.ESPN.Client.new(2025, league_id: "123")
```

### Return Types

**By default, all functions return Ecto structs** for type safety and better IDE support:

```elixir
{:ok, members} = TradeMachine.ESPN.Client.get_league_members(client)
first = List.first(members)
# Returns: %TradeMachine.ESPN.Types.LeagueMember{...}

# Access fields directly
first.display_name  # "647Raptors"
first.first_name    # "James"
first.is_league_manager  # false
```

For raw map responses, use the `:raw` option:

```elixir
{:ok, members} = TradeMachine.ESPN.Client.get_league_members(client, raw: true)
# Returns: [%{"displayName" => "647Raptors", ...}]
```

See [STRUCTS.md](./STRUCTS.md) for detailed documentation on all available structs and usage examples.

### Fetch League Data

```elixir
# Get all league members (returns structs)
{:ok, members} = TradeMachine.ESPN.Client.get_league_members(client)
# Returns: [%TradeMachine.ESPN.Types.LeagueMember{id: "...", display_name: "User1", ...}, ...]

# Get all fantasy teams (returns structs)
{:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client)
# Returns: [%TradeMachine.ESPN.Types.FantasyTeam{id: 1, name: "Team Name", ...}, ...]

# Get matchup schedule (returns structs)
{:ok, schedule} = TradeMachine.ESPN.Client.get_schedule(client)
# Returns: [%TradeMachine.ESPN.Types.ScheduleMatchup{id: 1, home: %{...}, away: %{...}}, ...]
```

### Fetch Team Roster

```elixir
# Get roster for team 1, scoring period 196 (returns struct)
{:ok, roster} = TradeMachine.ESPN.Client.get_roster(client, 1, 196)
# Returns: %TradeMachine.ESPN.Types.Roster{entries: [%RosterEntry{...}, ...]}

# Access roster entries
Enum.each(roster.entries, fn entry ->
  player = entry.player_pool_entry.player
  IO.puts("#{player.full_name} - Position: #{entry.lineup_slot_id}")
end)
```

### Fetch All Players (with pagination)

```elixir
# Fetch all MLB players (automatically handles pagination, returns structs)
{:ok, players} = TradeMachine.ESPN.Client.get_all_players(client)
# Returns: [%TradeMachine.ESPN.Types.PlayerPoolEntry{id: 12345, player: %PlayerInfo{...}}, ...]

# Access player data
first_player = List.first(players)
first_player.player.full_name  # "Jose Ramirez"
first_player.player.ownership.percent_owned  # 99.8

# Customize pagination settings
{:ok, players} = TradeMachine.ESPN.Client.get_all_players(client, 
  limit: 50,        # Players per page (default: 100)
  sleep_ms: 3000    # Sleep between requests (default: 5000)
)
```

## API Endpoints

The client supports these ESPN API endpoints:

- `GET /members` - League members
- `GET /teams?view=mTeam` - Fantasy teams with full details
- `GET /schedule?view=mScoreboard` - Matchup schedule
- `GET /?forTeamId=X&scoringPeriodId=Y&view=mRoster` - Team roster
- `GET /?view=kona_player_info` - All MLB players (paginated)

## Season Year Handling

The ESPN API uses different base URLs depending on the season:

- **2024+**: `https://lm-api-reads.fantasy.espn.com/apis/v3/games/flb/seasons/{year}/segments/0/leagues/{league_id}`
- **2017-2023**: `https://fantasy.espn.com/apis/v3/games/flb/seasons/{year}/segments/0/leagues/{league_id}`
- **Pre-2017**: `https://fantasy.espn.com/apis/v3/games/flb/leagueHistory/{league_id}?seasonId={year}`

The client automatically selects the correct base URL based on the year passed to `new/2`.

## Testing

Run the test script to verify your setup:

```bash
# From TradeMachineEx directory
mix run test_espn_client.exs
```

This will test all major API functions and display the results.

## Error Handling

All functions return `{:ok, result}` or `{:error, reason}` tuples:

```elixir
case TradeMachine.ESPN.Client.get_league_teams(client) do
  {:ok, teams} ->
    # Process teams
    IO.inspect(teams)

  {:error, {:http_error, status, body}} ->
    # Handle HTTP error
    Logger.error("HTTP #{status}: #{inspect(body)}")

  {:error, reason} ->
    # Handle other errors
    Logger.error("Request failed: #{inspect(reason)}")
end
```

## Rate Limiting

The `get_all_players/2` function includes automatic rate limiting:
- Sleeps 5 seconds (configurable) between paginated requests
- Fetches 100 players per request (configurable)
- Automatically stops when all players are fetched

## Future Enhancements

Potential improvements for future iterations:

1. **Automatic season detection** - Detect current season based on date
2. **Response parsing** - Convert raw maps to typed structs
3. **Caching** - Cache frequently accessed data
4. **Retry logic** - Automatic retries for transient failures
5. **More endpoints** - Add support for additional ESPN API endpoints as needed
