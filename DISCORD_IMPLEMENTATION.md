# Discord Trade Announcer Implementation

## Overview

The Discord Trade Announcer replaces the Slack trade announcement system from TradeMachineServer. It sends formatted trade announcements to Discord channels when trades are submitted.

## Architecture

```
lib/trade_machine/discord/
├── announcer.ex        # Public API - orchestrates the full flow
├── formatter.ex        # Pure formatting functions (no side effects)
├── embed_builder.ex    # Discord embed structure construction
├── client.ex           # Discord API wrapper (Nostrum)
└── embed_tester.ex     # Testing tool for embed format experiments
```

### Module Responsibilities

**`TradeMachine.Discord.Announcer`** - Main entry point. Fetches trade data from the database, resolves player/pick details from hydrated views, coordinates formatting, and sends via the client.

**`TradeMachine.Discord.Formatter`** - Pure functions that convert trade data into display strings. Uses CSV names for participant display, `[Level - MLB Team - Position]` suffix format, and skips missing information.

**`TradeMachine.Discord.EmbedBuilder`** - Builds Discord embed maps using the "Condensed" format (Option 2). All trade information goes in the description without separate fields. Handles uphold time calculation (11 PM Eastern, 24hr minimum).

**`TradeMachine.Discord.Client`** - Thin wrapper around `Nostrum.Api.Message.create/2`. Handles channel ID selection based on environment (production/staging) via environment variables.

## Usage

### Announcing a Trade

```elixir
# Announce to production
TradeMachine.Discord.Announcer.announce_trade("trade-uuid", :production)

# Announce to staging
TradeMachine.Discord.Announcer.announce_trade("trade-uuid", :staging)
```

### Building an Embed Without Sending

```elixir
{:ok, embed} = TradeMachine.Discord.Announcer.build_announcement("trade-uuid", :staging)
IO.inspect(embed, pretty: true)
```

### Sending to a Custom Channel (Testing)

```elixir
{:ok, embed} = TradeMachine.Discord.Announcer.build_announcement("trade-uuid", :staging)
TradeMachine.Discord.Client.send_embed(993_941_280_184_864_928, embed)
```

### Testing Embed Formats (EmbedTester)

The `EmbedTester` module uses sample data to preview different embed formats:

```elixir
TradeMachine.Discord.EmbedTester.test_all_formats(name_style: :csv_names)
TradeMachine.Discord.EmbedTester.test_format_2(name_style: :csv_names)
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|---|---|---|
| `DISCORD_BOT_TOKEN` | Bot authentication token | Yes (for Discord features) |
| `DISCORD_CHANNEL_ID_PRODUCTION` | Channel ID for production announcements | Yes (for production) |
| `DISCORD_CHANNEL_ID_STAGING` | Channel ID for staging/testing announcements | Yes (for staging) |

### Where to Set

- **Local dev**: `.env` (copy from `.env.development`)
- **Docker dev**: `docker-compose.yml` passes through from `.env`
- **Production**: `docker-compose.prod.yml` passes through from host environment
- **GitHub Actions**: Add to repository secrets if needed for CI

### Nostrum Configuration

Nostrum is configured conditionally in `config/runtime.exs`:
- Only starts when `DISCORD_BOT_TOKEN` is set
- Disabled in test environment
- Gateway intents: `:guilds`, `:guild_messages`

## Embed Format

The announcer uses the **Condensed** format (Option 2), chosen based on commissioner feedback:

```
🔊  A Trade Has Been Submitted  🔊

March 15, 2026 | Trade requested by @Ryan
Trading with: @Mikey
Trade will be upheld after: Sunday, March 16, 2026 11:00 PM

Ryan receives:
• Ketel Marte (Majors - ARI - 2B)
• Mikey's 2nd round Major League pick

Mikey receives:
• George Kirby (Majors - SEA - SP)
• Patrick Forbes (Minors)
• Ryan's 1st round Low Minors pick

🔗 Submit trades on FlexFoxFantasy TradeMachine by 11:00PM ET
```

### Formatting Rules

- **Participant names**: CSV name from User table (falls back to team name)
- **Major leaguers**: `Name (Majors - MLB Team - Position)` - skips missing fields
- **Minor leaguers**: `Name (Level - MLB Team - Position)` - skips missing fields
- **Unknown minor level**: Shows "Minors" instead of "Unknown Level"
- **Draft picks**: `Owner's Nth round League Type pick`
- **Discord mentions**: Uses `<@discord_user_id>` when available, falls back to `@display_name`
- **Uphold time**: Always 11 PM Eastern, minimum 24 hours from submission

## Data Flow

1. `Announcer.announce_trade/2` receives a trade ID and environment
2. Fetches trade with participants, teams, and owners from the appropriate repo
3. Queries `hydrated_majors` and `hydrated_minors` views for player details (position, team, level)
4. Queries `draft_pick` table for pick details (round, type, original owner)
5. Groups items by recipient team
6. Formats via `Formatter` functions (CSV names, player suffixes)
7. Builds embed via `EmbedBuilder` (condensed format with uphold time)
8. Sends via `Client` to the environment-appropriate Discord channel

## Testing

### Unit Tests

```bash
source .env.test && mix test test/trade_machine/discord/
```

Tests cover:
- Formatter: player formatting, pick formatting, name resolution, ordinals, mentions
- EmbedBuilder: embed structure, uphold time calculation (including DST)
- Client: channel ID resolution, error handling

### Manual IEx Testing

```elixir
# Test with real data on staging
TradeMachine.Discord.Announcer.announce_trade("some-trade-id", :staging)

# Or build embed and inspect without sending
{:ok, embed} = TradeMachine.Discord.Announcer.build_announcement("some-trade-id", :staging)
```

## Future Work

- Integrate with trade submission flow (call announcer when trade status changes to `:submitted`)
- Consider using an Oban job for async announcement (retry on failure)
- Add slash commands for trade lookup
- Add Discord event listeners for trade channel interactions
- Add `discord_user_id` field to User table for real Discord mentions
