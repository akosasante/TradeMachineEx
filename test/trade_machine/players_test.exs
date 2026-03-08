defmodule TradeMachine.PlayersTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: TradeMachine.Repo.Production, prefix: "test"

  import Ecto.Query

  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Team
  alias TradeMachine.Players

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Production)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradeMachine.Repo.Staging)

    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Production)
    TestHelper.set_search_path_for_sandbox(TradeMachine.Repo.Staging)

    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, {:shared, self()})
    Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, {:shared, self()})

    Ecto.Adapters.SQL.Sandbox.allow(TradeMachine.Repo.Production, self(), self())
    Ecto.Adapters.SQL.Sandbox.allow(TradeMachine.Repo.Staging, self(), self())

    :ok
  end

  # -------------------------------------------------------------------
  # Helper: build a raw ESPN player map (as returned by the API)
  # -------------------------------------------------------------------
  defp espn_player(id, full_name, opts \\ []) do
    pro_team_id = Keyword.get(opts, :pro_team_id, 10)
    default_position_id = Keyword.get(opts, :default_position_id, 6)
    on_team_id = Keyword.get(opts, :on_team_id, 0)
    status = Keyword.get(opts, :status, "FREEAGENT")

    %{
      "id" => id,
      "onTeamId" => on_team_id,
      "status" => status,
      "player" => %{
        "id" => id,
        "fullName" => full_name,
        "firstName" => full_name |> String.split() |> List.first(),
        "lastName" => full_name |> String.split() |> List.last(),
        "proTeamId" => pro_team_id,
        "defaultPositionId" => default_position_id,
        "eligibleSlots" => [default_position_id],
        "active" => true
      }
    }
  end

  defp insert_team!(repo, attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Team",
      status: :active,
      espn_id: nil
    }

    params = Map.merge(defaults, attrs)
    %Team{} |> Ecto.Changeset.change(params) |> repo.insert!()
  end

  defp insert_player!(repo, attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: "Test Player",
      league: :major,
      mlb_team: nil,
      player_data_id: nil,
      meta: nil,
      last_synced_at: nil,
      leagueTeamId: nil
    }

    params = Map.merge(defaults, attrs)
    %Player{} |> Ecto.Changeset.change(params) |> repo.insert!()
  end

  # -------------------------------------------------------------------
  # Phase 1: match by playerDataId
  # -------------------------------------------------------------------
  describe "sync_espn_player_data/3 - Phase 1 (match by playerDataId)" do
    test "updates existing player matched by playerDataId" do
      repo = TradeMachine.Repo.Production

      insert_player!(repo, %{
        name: "Aaron Judge",
        league: :major,
        player_data_id: 33_192,
        mlb_team: "NYY"
      })

      espn_players = [
        espn_player(33_192, "Aaron Judge", pro_team_id: 10, default_position_id: 9)
      ]

      {:ok, stats} = Players.sync_espn_player_data(espn_players, repo)

      assert stats.updated == 1
      assert stats.inserted == 0

      updated = repo.get_by!(Player, player_data_id: 33_192)
      assert updated.name == "Aaron Judge"
      assert updated.mlb_team == "NYY"
      assert updated.last_synced_at != nil
    end

    test "skips recently synced players within the idempotency window" do
      repo = TradeMachine.Repo.Production

      insert_player!(repo, %{
        name: "Aaron Judge",
        league: :major,
        player_data_id: 33_192,
        mlb_team: "NYY",
        last_synced_at: DateTime.utc_now()
      })

      espn_players = [
        espn_player(33_192, "Aaron Judge", pro_team_id: 10)
      ]

      {:ok, stats} = Players.sync_espn_player_data(espn_players, repo, skip_if_synced_within: 300)

      assert stats.skipped >= 1
      assert stats.updated == 0
    end

    test "does NOT skip if synced outside the idempotency window" do
      repo = TradeMachine.Repo.Production
      old_time = DateTime.add(DateTime.utc_now(), -600, :second)

      insert_player!(repo, %{
        name: "Aaron Judge",
        league: :major,
        player_data_id: 33_192,
        mlb_team: "NYY",
        last_synced_at: old_time
      })

      espn_players = [
        espn_player(33_192, "Aaron Judge", pro_team_id: 10)
      ]

      {:ok, stats} = Players.sync_espn_player_data(espn_players, repo, skip_if_synced_within: 300)

      assert stats.updated == 1
    end
  end

  # -------------------------------------------------------------------
  # Phase 2: claim unclaimed players
  # -------------------------------------------------------------------
  describe "sync_espn_player_data/3 - Phase 2 (claim unclaimed)" do
    test "claims unclaimed owned player via ownership match (onTeamId + name)" do
      repo = TradeMachine.Repo.Production

      team = insert_team!(repo, %{name: "Fantasy Team 1", espn_id: 5})

      insert_player!(repo, %{
        name: "Shohei Ohtani",
        league: :major,
        player_data_id: nil,
        mlb_team: "LAD",
        leagueTeamId: team.id
      })

      espn_players = [
        espn_player(39_832, "Shohei Ohtani",
          pro_team_id: 19,
          on_team_id: 5,
          status: "ONTEAM"
        )
      ]

      {:ok, stats} = Players.sync_espn_player_data(espn_players, repo)

      assert stats.updated == 1
      assert stats.inserted == 0

      claimed = repo.get_by!(Player, name: "Shohei Ohtani")
      assert claimed.player_data_id == 39_832
      assert claimed.mlb_team == "LAD"
    end

    test "falls back to name+team match when player is not owned" do
      repo = TradeMachine.Repo.Production

      insert_player!(repo, %{
        name: "Mike Trout",
        league: :major,
        player_data_id: nil,
        mlb_team: "LAA",
        leagueTeamId: nil
      })

      espn_players = [
        espn_player(4379, "Mike Trout", pro_team_id: 3, status: "FREEAGENT")
      ]

      {:ok, stats} = Players.sync_espn_player_data(espn_players, repo)

      assert stats.updated == 1
      assert stats.inserted == 0

      claimed = repo.get_by!(Player, name: "Mike Trout")
      assert claimed.player_data_id == 4379
    end

    test "disambiguates same-name players by mlbTeam" do
      repo = TradeMachine.Repo.Production

      insert_player!(repo, %{
        name: "Luis Garcia",
        league: :major,
        player_data_id: nil,
        mlb_team: "HOU"
      })

      espn_players = [
        espn_player(40_001, "Luis Garcia", pro_team_id: 18, default_position_id: 4),
        espn_player(40_002, "Luis Garcia", pro_team_id: 20, default_position_id: 6)
      ]

      {:ok, stats} = Players.sync_espn_player_data(espn_players, repo)

      claimed = repo.get_by!(Player, name: "Luis Garcia", mlb_team: "HOU")
      assert claimed.player_data_id == 40_001

      assert stats.updated == 1
      assert stats.inserted == 1
    end
  end

  # -------------------------------------------------------------------
  # Phase 3: insert new players
  # -------------------------------------------------------------------
  describe "sync_espn_player_data/3 - Phase 3 (inserts)" do
    test "inserts ESPN players not found in DB" do
      repo = TradeMachine.Repo.Production

      espn_players = [
        espn_player(99_001, "New Player One", pro_team_id: 1),
        espn_player(99_002, "New Player Two", pro_team_id: 2)
      ]

      {:ok, stats} = Players.sync_espn_player_data(espn_players, repo)

      assert stats.inserted == 2
      assert stats.updated == 0

      p1 = repo.get_by!(Player, player_data_id: 99_001)
      assert p1.name == "New Player One"
      assert p1.league == :major
      assert p1.mlb_team == "BAL"

      p2 = repo.get_by!(Player, player_data_id: 99_002)
      assert p2.name == "New Player Two"
      assert p2.mlb_team == "BOS"
    end

    test "stores ESPN JSON in meta.espnPlayer and position" do
      repo = TradeMachine.Repo.Production

      espn_players = [
        espn_player(88_001, "Test Meta Player", pro_team_id: 10, default_position_id: 6)
      ]

      {:ok, _stats} = Players.sync_espn_player_data(espn_players, repo)

      player =
        Player
        |> Ecto.Query.where([p], p.player_data_id == 88_001)
        |> Ecto.Query.select_merge([p], %{meta: p.meta})
        |> repo.one!()

      assert player.meta["espnPlayer"]["id"] == 88_001
      assert player.meta["espnPlayer"]["player"]["fullName"] == "Test Meta Player"
      assert player.meta["position"] == "SS"
    end
  end

  # -------------------------------------------------------------------
  # Retired / missing from ESPN
  # -------------------------------------------------------------------
  describe "sync_espn_player_data/3 - retired/missing" do
    test "does not delete DB players missing from ESPN" do
      repo = TradeMachine.Repo.Production

      insert_player!(repo, %{
        name: "Retired Guy",
        league: :major,
        player_data_id: 11_111,
        mlb_team: "NYY"
      })

      espn_players = [
        espn_player(99_999, "Some Other Player", pro_team_id: 1)
      ]

      {:ok, _stats} = Players.sync_espn_player_data(espn_players, repo)

      assert repo.get_by(Player, player_data_id: 11_111) != nil
    end
  end

  # -------------------------------------------------------------------
  # get_syncable_players/1
  # -------------------------------------------------------------------
  describe "get_syncable_players/1" do
    test "returns major league players" do
      repo = TradeMachine.Repo.Production
      insert_player!(repo, %{name: "Major Guy", league: :major, player_data_id: nil})
      insert_player!(repo, %{name: "Minor Guy", league: :minor, player_data_id: nil})

      players = Players.get_syncable_players(repo)
      names = Enum.map(players, & &1.name)

      assert "Major Guy" in names
      refute "Minor Guy" in names
    end

    test "returns minor leaguers who have a player_data_id" do
      repo = TradeMachine.Repo.Production
      insert_player!(repo, %{name: "Promoted Minor", league: :minor, player_data_id: 54_321})
      insert_player!(repo, %{name: "Unknown Minor", league: :minor, player_data_id: nil})

      players = Players.get_syncable_players(repo)
      names = Enum.map(players, & &1.name)

      assert "Promoted Minor" in names
      refute "Unknown Minor" in names
    end

    test "returns empty list when no syncable players exist" do
      repo = TradeMachine.Repo.Production
      insert_player!(repo, %{name: "Unsynced Minor", league: :minor, player_data_id: nil})

      players = Players.get_syncable_players(repo)
      names = Enum.map(players, & &1.name)

      refute "Unsynced Minor" in names
    end
  end

  # -------------------------------------------------------------------
  # Meta merging
  # -------------------------------------------------------------------
  describe "sync_espn_player_data/3 - meta merging" do
    test "preserves existing meta keys when updating" do
      repo = TradeMachine.Repo.Production

      insert_player!(repo, %{
        name: "Player With Meta",
        league: :major,
        player_data_id: 77_001,
        mlb_team: "NYY",
        meta: %{"minorLeaguePlayerFromSheet" => %{"position" => "SS"}, "customKey" => "value"}
      })

      espn_players = [
        espn_player(77_001, "Player With Meta", pro_team_id: 10)
      ]

      {:ok, _stats} = Players.sync_espn_player_data(espn_players, repo)

      player =
        Player
        |> Ecto.Query.where([p], p.player_data_id == 77_001)
        |> Ecto.Query.select_merge([p], %{meta: p.meta})
        |> repo.one!()

      assert player.meta["minorLeaguePlayerFromSheet"] == %{"position" => "SS"}
      assert player.meta["customKey"] == "value"
      assert player.meta["espnPlayer"] != nil
      assert player.meta["position"] != nil
    end
  end
end
