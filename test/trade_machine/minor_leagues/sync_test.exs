defmodule TradeMachine.MinorLeagues.SyncTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Team
  alias TradeMachine.Data.User
  alias TradeMachine.MinorLeagues.Sync

  @repo TradeMachine.Repo.Production

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(@repo)
    TestHelper.set_search_path_for_sandbox(@repo)
    Ecto.Adapters.SQL.Sandbox.mode(@repo, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.allow(@repo, self(), self())

    team = insert_team!(@repo, %{name: "Test Team"})
    user = insert_user!(@repo, %{csv_name: "Flex", teamId: team.id, display_name: "Flex Owner"})

    team2 = insert_team!(@repo, %{name: "Test Team 2"})

    _user2 =
      insert_user!(@repo, %{csv_name: "Newton", teamId: team2.id, display_name: "Newton Owner"})

    %{team: team, user: user, team2: team2}
  end

  defp insert_team!(repo, attrs) do
    defaults = %{id: Ecto.UUID.generate(), name: "Team", status: :active}
    params = Map.merge(defaults, attrs)
    %Team{} |> Ecto.Changeset.change(params) |> repo.insert!()
  end

  defp insert_user!(repo, attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      display_name: "Test User",
      email: "test-#{System.unique_integer([:positive])}@example.com",
      status: :active,
      role: :owner
    }

    params = Map.merge(defaults, attrs)
    %User{} |> Ecto.Changeset.change(params) |> repo.insert!()
  end

  defp insert_player!(repo, attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Player",
      league: :minor,
      mlb_team: nil,
      meta: nil,
      last_synced_at: nil,
      leagueTeamId: nil
    }

    params = Map.merge(defaults, attrs)
    %Player{} |> Ecto.Changeset.change(params) |> repo.insert!()
  end

  defp parsed_player(attrs \\ %{}) do
    defaults = %{
      name: "Test Prospect",
      league_level: "HM",
      position: "P",
      mlb_team: "NYY",
      owner_csv_name: "Flex"
    }

    Map.merge(defaults, attrs)
  end

  describe "sync_from_sheet/2 - inserting new players" do
    test "inserts a new minor leaguer when no match found", %{team: team} do
      parsed = [parsed_player(%{name: "New Prospect", mlb_team: "CLE"})]
      {:ok, stats} = Sync.sync_from_sheet(parsed, @repo)

      assert stats.inserted == 1
      assert stats.matched == 0

      player =
        @repo.one!(
          from(p in Player, where: p.name == "New Prospect", select: %{p | meta: p.meta})
        )

      assert player.league == :minor
      assert player.mlb_team == "CLE"
      assert player.leagueTeamId == team.id
      assert player.meta["minorLeaguePlayerFromSheet"]["position"] == "P"
      assert player.meta["minorLeaguePlayerFromSheet"]["leagueLevel"] == "HM"
    end

    test "inserts multiple players for different owners", %{team: team, team2: team2} do
      parsed = [
        parsed_player(%{name: "Player A", owner_csv_name: "Flex"}),
        parsed_player(%{name: "Player B", owner_csv_name: "Newton"})
      ]

      {:ok, stats} = Sync.sync_from_sheet(parsed, @repo)
      assert stats.inserted == 2

      player_a = @repo.one!(from(p in Player, where: p.name == "Player A"))
      assert player_a.leagueTeamId == team.id

      player_b = @repo.one!(from(p in Player, where: p.name == "Player B"))
      assert player_b.leagueTeamId == team2.id
    end
  end

  describe "sync_from_sheet/2 - matching existing players" do
    test "matches by meta.minorLeaguePlayerFromSheet and updates owner", %{
      team: team,
      team2: team2
    } do
      insert_player!(@repo, %{
        name: "Andrew Walters",
        league: :minor,
        mlb_team: "CLE",
        leagueTeamId: team2.id,
        meta: %{
          "minorLeaguePlayerFromSheet" => %{
            "name" => "Andrew Walters",
            "position" => "P",
            "leagueLevel" => "HM",
            "mlbTeam" => "CLE"
          }
        }
      })

      parsed = [
        parsed_player(%{
          name: "Andrew Walters",
          position: "P",
          league_level: "HM",
          mlb_team: "CLE",
          owner_csv_name: "Flex"
        })
      ]

      {:ok, stats} = Sync.sync_from_sheet(parsed, @repo)
      assert stats.matched == 1
      assert stats.inserted == 0

      player = @repo.one!(from(p in Player, where: p.name == "Andrew Walters"))
      assert player.leagueTeamId == team.id
    end

    test "matches by fallback (name + mlb_team) when no meta exists", %{team: team} do
      insert_player!(@repo, %{
        name: "Bryan Ramos",
        league: :minor,
        mlb_team: "CWS",
        meta: nil
      })

      parsed = [
        parsed_player(%{
          name: "Bryan Ramos",
          position: "3B",
          league_level: "HM",
          mlb_team: "CWS",
          owner_csv_name: "Flex"
        })
      ]

      {:ok, stats} = Sync.sync_from_sheet(parsed, @repo)
      assert stats.matched == 1

      player =
        @repo.one!(from(p in Player, where: p.name == "Bryan Ramos", select: %{p | meta: p.meta}))

      assert player.leagueTeamId == team.id
      assert player.meta["minorLeaguePlayerFromSheet"]["position"] == "3B"
    end
  end

  describe "sync_from_sheet/2 - clearing stale owners" do
    test "nullifies leagueTeamId for owned minors not on sheet", %{team: team} do
      stale_player =
        insert_player!(@repo, %{
          name: "Stale Prospect",
          league: :minor,
          mlb_team: "SEA",
          leagueTeamId: team.id,
          meta: %{
            "minorLeaguePlayerFromSheet" => %{
              "name" => "Stale Prospect",
              "position" => "OF",
              "leagueLevel" => "LM",
              "mlbTeam" => "SEA"
            }
          }
        })

      parsed = [parsed_player(%{name: "Fresh Prospect", mlb_team: "NYY"})]
      {:ok, stats} = Sync.sync_from_sheet(parsed, @repo)

      assert stats.cleared == 1

      updated = @repo.get!(Player, stale_player.id)
      assert is_nil(updated.leagueTeamId)
    end

    test "does not clear unowned minors" do
      insert_player!(@repo, %{
        name: "Unowned Prospect",
        league: :minor,
        mlb_team: "SEA",
        leagueTeamId: nil
      })

      parsed = [parsed_player(%{name: "Other Prospect"})]
      {:ok, stats} = Sync.sync_from_sheet(parsed, @repo)

      assert stats.cleared == 0
    end
  end

  describe "sync_from_sheet/2 - owner resolution" do
    test "skips players with unresolvable owners" do
      parsed = [parsed_player(%{name: "Orphan Player", owner_csv_name: "NonExistentOwner"})]
      {:ok, stats} = Sync.sync_from_sheet(parsed, @repo)

      assert stats.skipped_no_owner == 1
      assert stats.inserted == 0

      assert @repo.one(from(p in Player, where: p.name == "Orphan Player")) == nil
    end
  end

  describe "sync_from_sheet/2 - empty input" do
    test "clears all owned minors when sheet is empty", %{team: team} do
      insert_player!(@repo, %{
        name: "Owned Minor",
        league: :minor,
        mlb_team: "NYY",
        leagueTeamId: team.id
      })

      {:ok, stats} = Sync.sync_from_sheet([], @repo)

      assert stats.matched == 0
      assert stats.inserted == 0
      assert stats.cleared == 1
    end
  end
end
