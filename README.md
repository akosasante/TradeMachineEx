# TradeMachineEx

TradeMachineEx is the Elixir-based job processing service for the TradeMachine fantasy baseball trading platform. This application handles scheduled data imports, background processing, and concurrent job execution with built-in retry mechanisms.

## Purpose

- **Scheduled Jobs**: Automated data synchronization and updates from external sources
- **Data Processing**: Import and processing of Excel sheets and external APIs
- **Concurrent Processing**: Leverages Elixir's actor model for efficient concurrent job handling
- **Reliability**: Built-in retry logic and fault tolerance for critical background tasks

## Getting Started

### Prerequisites
- Elixir 1.18+
- Erlang/OTP 27+
- PostgreSQL database

### Development Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Set up database:
   ```bash
   mix ecto.setup
   ```

3. Start development server (recommended):
   ```bash
   ./start-dev.sh --skip-infrastructure
   ```

   Or start locally:
   ```bash
   mix phx.server
   ```

### Testing

Run tests locally:
```bash
./test.sh
```

Run specific test:
```bash
./test.sh test/schema_validation_test.exs
```

### Code Quality

- **Linting**: `mix credo`
- **Type Checking**: `mix dialyzer`

## Architecture

TradeMachineEx is designed to complement the main TradeMachine TypeScript backend by handling compute-intensive and scheduled operations that benefit from Elixir's concurrency model and fault-tolerance capabilities.