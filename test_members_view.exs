# Quick test for members with mNav view
# Run with: export $(grep -v '^#' .env | xargs) && mix run test_members_view.exs

Application.ensure_all_started(:req)
Application.ensure_all_started(:finch)
Finch.start_link(name: Req.Finch)

IO.puts("\n=== Testing Members with mNav view ===\n")

client = TradeMachine.ESPN.Client.new(2025)

case TradeMachine.ESPN.Client.get_league_members(client) do
  {:ok, members} ->
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

  {:error, reason} ->
    IO.puts("✗ Failed: #{inspect(reason)}")
end
