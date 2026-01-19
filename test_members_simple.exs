# Minimal test for members with mNav view - no Phoenix app
# Run with: export $(grep -v '^#' .env | xargs) && mix run --no-start test_members_simple.exs

# Start only what we need
Application.ensure_all_started(:logger)
Application.ensure_all_started(:jason)
Application.ensure_all_started(:req)
Finch.start_link(name: Req.Finch)

IO.puts("\n=== Testing Members with mNav view ===\n")

# Get credentials from Application config (set in runtime.exs)
espn_cookie = Application.get_env(:trade_machine, :espn_cookie) || System.get_env("ESPN_COOKIE")
espn_swid = Application.get_env(:trade_machine, :espn_swid) || System.get_env("ESPN_SWID")

league_id =
  Application.get_env(:trade_machine, :espn_league_id) || System.get_env("ESPN_LEAGUE_ID") ||
    "545"

if is_nil(espn_cookie) or is_nil(espn_swid) do
  IO.puts("ERROR: ESPN credentials not found!")
  System.halt(1)
end

# Create client manually
base_url =
  "https://lm-api-reads.fantasy.espn.com/apis/v3/games/flb/seasons/2025/segments/0/leagues/#{league_id}"

req =
  Req.new(
    base_url: base_url,
    headers: [{"cookie", "espn_s2=#{espn_cookie}; SWID=#{espn_swid};"}],
    receive_timeout: 30_000
  )

IO.puts("Fetching members with ?view=mNav...")

case Req.get(req, url: "/members", params: [view: "mNav"]) do
  {:ok, %{status: 200, body: members}} ->
    IO.puts("✓ Success! Found #{length(members)} members with full details\n")

    # Show first member with all fields
    first = List.first(members)
    IO.puts("First member details:")
    IO.puts("  Display Name: #{first["displayName"]}")
    IO.puts("  First Name: #{first["firstName"]}")
    IO.puts("  Last Name: #{first["lastName"]}")
    IO.puts("  ID: #{first["id"]}")
    IO.puts("  Is League Creator: #{first["isLeagueCreator"]}")
    IO.puts("  Is League Manager: #{first["isLeagueManager"]}")
    IO.puts("")

    # Show all member names
    IO.puts("All members:")

    Enum.each(members, fn member ->
      manager_badge = if member["isLeagueManager"], do: " 👑", else: ""
      creator_badge = if member["isLeagueCreator"], do: " ⭐", else: ""

      IO.puts(
        "  - #{member["firstName"]} #{member["lastName"]} (@#{member["displayName"]})#{manager_badge}#{creator_badge}"
      )
    end)

  {:ok, %{status: status, body: body}} ->
    IO.puts("✗ Failed with HTTP status: #{status}")
    IO.puts("Body: #{inspect(body)}")

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}")
end
