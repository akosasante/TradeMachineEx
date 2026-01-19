# ESPN API Client - Ecto Structs

The ESPN API client now returns typed Ecto structs by default, providing better type safety and IDE autocomplete support.

## Overview

All client functions return Ecto embedded schemas instead of raw maps. This provides:
- **Type safety** - Compile-time checks for field access
- **IDE support** - Autocomplete for struct fields
- **Documentation** - Clear structure of API responses
- **Validation** - Optional changeset validation

## Available Structs

### LeagueMember

```elixir
%TradeMachine.ESPN.Types.LeagueMember{
  id: String.t(),
  display_name: String.t(),
  first_name: String.t(),
  last_name: String.t(),
  is_league_creator: boolean(),
  is_league_manager: boolean()
}
```

### FantasyTeam

```elixir
%TradeMachine.ESPN.Types.FantasyTeam{
  id: integer(),
  abbrev: String.t(),
  name: String.t(),
  location: String.t(),
  nickname: String.t(),
  owners: [String.t()],
  primary_owner: String.t(),
  logo: String.t(),
  logo_type: String.t(),
  points: float(),
  waiver_rank: integer(),
  values_by_stat: map(),
  record: TradeMachine.ESPN.Types.TeamRecord.t(),
  transaction_counter: TradeMachine.ESPN.Types.TransactionCounter.t()
}
```

### PlayerPoolEntry

```elixir
%TradeMachine.ESPN.Types.PlayerPoolEntry{
  id: integer(),
  on_team_id: integer(),
  status: String.t(),
  player: TradeMachine.ESPN.Types.PlayerInfo.t()
}
```

### ScheduleMatchup

```elixir
%TradeMachine.ESPN.Types.ScheduleMatchup{
  id: integer(),
  winner: String.t(),
  home: TradeMachine.ESPN.Types.MatchupScore.t(),
  away: TradeMachine.ESPN.Types.MatchupScore.t()
}
```

### Roster

```elixir
%TradeMachine.ESPN.Types.Roster{
  entries: [TradeMachine.ESPN.Types.RosterEntry.t()]
}
```

## Usage Examples

### Default - Returns Structs

```elixir
# Get members as structs
{:ok, members} = TradeMachine.ESPN.Client.get_league_members(client)
first = List.first(members)

# Access fields directly
first.display_name  # "647Raptors"
first.first_name    # "James"
first.last_name     # "Gumatay"
first.is_league_manager  # false

# Pattern match on struct type
%TradeMachine.ESPN.Types.LeagueMember{
  first_name: fname,
  last_name: lname,
  is_league_manager: true
} = first
```

### Get Teams with Nested Structs

```elixir
{:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client)
first_team = List.first(teams)

# Access nested record
first_team.record.overall.wins  # 10
first_team.record.overall.losses  # 5
first_team.record.overall.percentage  # 0.667

# Access transaction counter
first_team.transaction_counter.acquisitions  # 15
first_team.transaction_counter.trades  # 3
```

### Get Players with Ownership Data

```elixir
{:ok, players} = TradeMachine.ESPN.Client.get_all_players(client, limit: 100)
first_player = List.first(players)

# Access player info
first_player.player.full_name  # "Jose Ramirez"
first_player.player.pro_team_id  # 5 (Cleveland)
first_player.player.injured  # false

# Access ownership stats
first_player.player.ownership.percent_owned  # 99.8
first_player.player.ownership.percent_started  # 95.2
```

### Get Schedule with Matchup Details

```elixir
{:ok, schedule} = TradeMachine.ESPN.Client.get_schedule(client)
matchup = List.first(schedule)

# Access matchup info
matchup.id  # 1
matchup.winner  # "HOME" or "AWAY" or nil

# Access home team score
matchup.home.team_id  # 1
matchup.home.total_points  # 45.5
matchup.home.cumulative_score.wins  # 8
matchup.home.cumulative_score.losses  # 2

# Access away team score
matchup.away.team_id  # 2
matchup.away.total_points  # 38.2
```

### Get Roster with Player Details

```elixir
{:ok, roster} = TradeMachine.ESPN.Client.get_roster(client, 1, 196)

# Iterate over roster entries
Enum.each(roster.entries, fn entry ->
  player = entry.player_pool_entry.player
  IO.puts("#{player.full_name} - Slot: #{entry.lineup_slot_id}")
end)

# Filter by lineup slot
starters = Enum.filter(roster.entries, fn entry ->
  entry.lineup_slot_id < 10  # Starting positions
end)
```

## Raw Mode

If you need the original map responses (e.g., for debugging or custom parsing), use the `:raw` option:

```elixir
# Get raw maps instead of structs
{:ok, raw_members} = TradeMachine.ESPN.Client.get_league_members(client, raw: true)
first = List.first(raw_members)

# Access with string keys
first["displayName"]  # "647Raptors"
first["firstName"]    # "James"
first["isLeagueManager"]  # false
```

All client functions support the `:raw` option:
- `get_league_members(client, raw: true)`
- `get_league_teams(client, raw: true)`
- `get_schedule(client, raw: true)`
- `get_roster(client, team_id, period_id, raw: true)`
- `get_all_players(client, raw: true)`

## Pattern Matching Examples

### Find League Managers

```elixir
{:ok, members} = TradeMachine.ESPN.Client.get_league_members(client)

managers = 
  members
  |> Enum.filter(& &1.is_league_manager)
  |> Enum.map(& "#{&1.first_name} #{&1.last_name}")

# ["Jatheesh S", "Nick Penner", "Cam MacInnis"]
```

### Find Teams by Owner

```elixir
{:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client)

my_teams = 
  teams
  |> Enum.filter(fn team -> 
    owner_id in (team.owners || [])
  end)
```

### Find Injured Players on Roster

```elixir
{:ok, roster} = TradeMachine.ESPN.Client.get_roster(client, team_id, period_id)

injured_players =
  roster.entries
  |> Enum.map(& &1.player_pool_entry.player)
  |> Enum.filter(& &1.injured)
  |> Enum.map(& {&1.full_name, &1.injury_status})

# [{"Player Name", "DTD"}, ...]
```

### Calculate Team Stats

```elixir
{:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client)

standings =
  teams
  |> Enum.map(fn team ->
    %{
      name: "#{team.location} #{team.nickname}",
      wins: team.record.overall.wins,
      losses: team.record.overall.losses,
      pct: team.record.overall.percentage,
      points_for: team.record.overall.points_for
    }
  end)
  |> Enum.sort_by(& &1.pct, :desc)
```

## Type Specs

All struct modules include proper type specs:

```elixir
@type t :: %__MODULE__{
  id: String.t(),
  display_name: String.t(),
  # ...
}
```

This enables Dialyzer type checking and better IDE support.

## Changesets (Optional)

Some structs include changeset functions for validation:

```elixir
alias TradeMachine.ESPN.Types.LeagueMember

# Create changeset from API data
changeset = LeagueMember.changeset(%LeagueMember{}, api_data)

if changeset.valid? do
  member = Ecto.Changeset.apply_changes(changeset)
  # Use validated member
end
```

## Testing

Run the test suite to verify struct functionality:

```bash
export $(grep -v '^#' .env | xargs) && mix run --no-start test_structs_quick.exs
```

This will test:
- Struct creation from API responses
- Field access
- Nested struct relationships
- Raw mode fallback
