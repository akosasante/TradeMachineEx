defmodule TradeMachine.TeamsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TradeMachine.Data.Team
  alias TradeMachine.ESPN.Types.FantasyTeam
  alias TradeMachine.Teams

  @repo TradeMachine.Repo.Production

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(@repo)
    TestHelper.set_search_path_for_sandbox(@repo)
    :ok
  end

  defp insert_team!(attrs) do
    defaults = %{id: Ecto.UUID.generate(), name: "Team", status: :active, espn_id: nil}
    params = Map.merge(defaults, attrs)
    %Team{} |> Ecto.Changeset.change(params) |> @repo.insert!()
  end

  # espn_team has load_in_query: false — must be fetched explicitly
  defp get_team_with_espn_data(espn_id) do
    Team
    |> where([t], t.espn_id == ^espn_id)
    |> select([t], %{t | espn_team: t.espn_team})
    |> @repo.one!()
  end

  defp espn_team(id, name) do
    %FantasyTeam{
      id: id,
      name: name,
      abbrev: "TST",
      location: "Test",
      nickname: "Testers",
      owners: ["user-abc"],
      primary_owner: "user-abc",
      logo: "https://example.com/logo.png",
      logo_type: "vector"
    }
  end

  describe "sync_espn_team_data/2" do
    test "updates a team matching by espn_id" do
      insert_team!(%{espn_id: 1, name: "Old Name"})

      {:ok, stats} = Teams.sync_espn_team_data([espn_team(1, "New Name")], @repo)

      assert stats.updated == 1
      assert stats.skipped == 0

      team = @repo.get_by!(Team, espn_id: 1)
      assert team.name == "New Name"
    end

    test "stores ESPN data in the espn_team JSON column" do
      insert_team!(%{espn_id: 2, name: "Team Two"})

      {:ok, _stats} = Teams.sync_espn_team_data([espn_team(2, "Team Two")], @repo)

      team = get_team_with_espn_data(2)
      espn_data = team.espn_team
      assert espn_data["name"] == "Team Two"
      assert espn_data["abbrev"] == "TST"
    end

    test "skips ESPN teams with no matching DB record" do
      {:ok, stats} = Teams.sync_espn_team_data([espn_team(999, "Unknown")], @repo)

      assert stats.updated == 0
      assert stats.skipped == 1
    end

    test "handles a mix of matched and unmatched teams" do
      insert_team!(%{espn_id: 10, name: "Alpha"})
      insert_team!(%{espn_id: 11, name: "Beta"})

      espn_teams = [
        espn_team(10, "Alpha Updated"),
        espn_team(11, "Beta Updated"),
        espn_team(99, "Ghost Team")
      ]

      {:ok, stats} = Teams.sync_espn_team_data(espn_teams, @repo)

      assert stats.updated == 2
      assert stats.skipped == 1
    end

    test "returns {:ok, %{updated: 0, skipped: 0}} for empty input" do
      {:ok, stats} = Teams.sync_espn_team_data([], @repo)
      assert stats == %{updated: 0, skipped: 0}
    end

    test "can be called without explicit repo (uses default Production repo)" do
      {:ok, stats} = Teams.sync_espn_team_data([])
      assert stats == %{updated: 0, skipped: 0}
    end

    test "updates last_synced_at on each matched team" do
      before = DateTime.utc_now()
      insert_team!(%{espn_id: 5, name: "Timed Team"})

      {:ok, _stats} = Teams.sync_espn_team_data([espn_team(5, "Timed Team")], @repo)

      team = @repo.get_by!(Team, espn_id: 5)
      assert DateTime.compare(team.last_synced_at, before) in [:eq, :gt]
    end

    test "converts nested FantasyTeam structs to plain maps in espn_team column" do
      insert_team!(%{espn_id: 7, name: "Nested"})

      team_with_record = %FantasyTeam{
        espn_team(7, "Nested")
        | record: nil,
          transaction_counter: nil
      }

      {:ok, _stats} = Teams.sync_espn_team_data([team_with_record], @repo)

      team = get_team_with_espn_data(7)
      assert is_map(team.espn_team)
      refute match?(%FantasyTeam{}, team.espn_team)
    end
  end
end
