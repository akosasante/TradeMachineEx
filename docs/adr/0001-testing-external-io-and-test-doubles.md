# ADR 0001: Testing External I/O and Test Doubles

**Status:** Accepted  
**Date:** 2026-04-11  
**Context:** Discord trade-action DMs feature (PR #28)

## Decision

### Stubbing library-owned I/O (Nostrum / Discord)

When production code calls a third-party library that owns the HTTP stack (e.g. `Nostrum.Api.*` for Discord), we introduce a thin **behaviour + Application-config double** rather than trying to intercept or replace the library's internal networking.

**Pattern:**

1. Define a behaviour in `lib/` with `@callback` for the boundary function(s).
2. Write a default implementation that delegates to the real library (e.g. `TradeMachine.Discord.Client`).
3. Write a test module in `test/support/` that `@impl`s the behaviour and returns canned values.
4. Register the test module in `test/test_helper.exs` via `Application.put_env/3`.
5. Production code resolves the implementation via `Application.get_env(:trade_machine, :key, DefaultModule)`.

The compiler enforces callback arity/name on both sides when both modules declare `@impl true`.

**Existing examples:** `:discord_interaction_api` and `:discord_application_command_api` in `test/test_helper.exs` with stub modules in `test/support/discord_api_stub.ex`.

### Banned: `mock` (Hex) and Meck

Runtime function patching (replacing a module's function at the BEAM level during a test) is **not allowed** in this repo. It is global, not process-safe, breaks `async: true`, and makes failures hard to reproduce.

### When to use Bypass

**Bypass** opens a real TCP port and serves HTTP responses. Use it **only** when:

- **Your application code** controls the HTTP client's base URL (via config or function argument), and
- You want to assert on the **HTTP request** your code sends (path, headers, body).

This fits boundaries where we use `Req` with configurable options (ESPN client, sheet fetchers, etc.).

**Do not use Bypass for Nostrum-backed paths.** Nostrum owns the HTTP connection to Discord, hardcodes the API host, and manages auth headers internally. Pointing Nostrum at a Bypass port is unsupported, fragile across library upgrades, and would mostly test Nostrum's HTTP layer rather than our embed/repo logic.

### When to use Req.Test

`Req.Test` (already used in `config/test.exs`) is preferred over Bypass when:

- The boundary uses `Req` as its HTTP client, and
- You want an in-process plug-based stub (no real TCP; faster, no port conflicts).

Current usages: `:espn_req_options`, `:espn_search_req_options`, `:sheet_fetcher_req_options`, `:draft_picks_sheet_fetcher_req_options`.

Choose Bypass over `Req.Test` only when you need to test real TCP behavior (connection timeouts, TLS, chunked responses) or the client is not `Req`.

### When to add Mox (or Hammox / Mimic)

The behaviour + hand-rolled test module approach is sufficient **until:**

- Multiple test files need **different return values per test case** from the same boundary (Mox's `expect/3` is more ergonomic than swapping `Application.put_env` or managing Agent state per test).
- A behaviour has **many callbacks** and hand-rolling a full implementation for each test scenario becomes verbose.
- You want **strict call-count verification** ("called exactly once with these args") without writing Agent/ETS bookkeeping.

When any of these apply, add `{:mox, "~> 1.0", only: :test}` to `mix.exs` and `Mox.defmock` in `test/support/`. Optionally layer **Hammox** on top for typespec validation of mock args/returns.

**Mimic** (stubs existing modules without behaviours) is an allowed alternative if the team prefers it, but behaviours should still be defined for new boundaries — they document the contract regardless of which mock library is used.

## Consequences

- New external I/O boundaries follow the behaviour + `Application.get_env` pattern.
- `test/test_helper.exs` is the single registration point for test doubles.
- `coveralls.json` may skip thin I/O wrapper modules (e.g. `discord/client.ex`) that are intentionally not exercised in CI.
- Mox/Hammox adoption is a future opt-in per the criteria above, not a prerequisite.
