defmodule TradeMachine.DraftPicks.SyncTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.Team
  alias TradeMachine.Data.User
  alias TradeMachine.DraftPicks.Sync

  @repo TradeMachine.Repo.Production

  # The test setup configures resolve_season/0 to return 2025 (the minor league
  # season). Major league picks therefore use 2026 (minor + 1).
  @minor_season 2025
  @major_season @minor_season + 1

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(@repo)
    TestHelper.set_search_path_for_sandbox(@repo)
    Ecto.Adapters.SQL.Sandbox.mode(@repo, {:shared, self()})

    team_a = insert_team!(@repo, %{name: "Team Alpha"})
    _user_a = insert_user!(@repo, %{csv_name: "Alpha", teamId: team_a.id})

    team_b = insert_team!(@repo, %{name: "Team Beta"})
    _user_b = insert_user!(@repo, %{csv_name: "Beta", teamId: team_b.id})

    # Configure season thresholds so resolve_season/0 succeeds in tests.
    # Uses a date far in the past so today always matches the first entry.
    original_thresholds = Application.get_env(:trade_machine, :draft_picks_season_thresholds)

    Application.put_env(:trade_machine, :draft_picks_season_thresholds, [
      {~D[2000-01-01], @minor_season}
    ])

    on_exit(fn ->
      Application.put_env(:trade_machine, :draft_picks_season_thresholds, original_thresholds)
    end)

    %{team_a: team_a, team_b: team_b}
  end

  # ---------------------------------------------------------------------------
  # Factory helpers
  # ---------------------------------------------------------------------------

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

  defp parsed_pick(attrs \\ %{}) do
    defaults = %{
      type: :majors,
      round: Decimal.new("1.0"),
      original_owner_csv: "Alpha",
      current_owner_csv: "Alpha",
      pick_number: 5
    }

    Map.merge(defaults, attrs)
  end

  defp find_pick(repo, type, round, orig_team_id, season) do
    DraftPick
    |> where(
      [p],
      p.type == ^type and
        p.season == ^season and
        p.originalOwnerId == ^orig_team_id
    )
    |> where([p], fragment("round = ?::numeric", ^round))
    |> repo.one()
  end

  # ---------------------------------------------------------------------------
  # sync_from_sheet/2
  # ---------------------------------------------------------------------------

  describe "sync_from_sheet/2 - inserting new picks" do
    test "inserts a new major league pick with season = minor_season + 1", %{team_a: team_a} do
      picks = [parsed_pick()]
      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)

      assert stats.upserted == 1
      assert stats.skipped_no_owner == 0

      pick = find_pick(@repo, :majors, Decimal.new("1.0"), team_a.id, @major_season)
      assert pick != nil
      assert pick.season == @major_season
      assert pick.pick_number == 5
      assert pick.currentOwnerId == team_a.id
      assert pick.originalOwnerId == team_a.id
      assert pick.last_synced_at != nil
    end

    test "inserts high-minor and low-minor picks with season = minor_season", %{team_a: team_a} do
      picks = [
        parsed_pick(%{type: :high, round: Decimal.new("1.0"), pick_number: 2}),
        parsed_pick(%{type: :low, round: Decimal.new("1.0"), pick_number: 3})
      ]

      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)
      assert stats.upserted == 2

      hm = find_pick(@repo, :high, Decimal.new("1.0"), team_a.id, @minor_season)
      assert hm != nil
      assert hm.season == @minor_season

      lm = find_pick(@repo, :low, Decimal.new("1.0"), team_a.id, @minor_season)
      assert lm != nil
      assert lm.season == @minor_season
    end

    test "inserts picks of all three types with correct seasons", %{team_a: team_a} do
      picks = [
        parsed_pick(%{type: :majors, round: Decimal.new("1.0"), pick_number: 1}),
        parsed_pick(%{type: :high, round: Decimal.new("1.0"), pick_number: 2}),
        parsed_pick(%{type: :low, round: Decimal.new("1.0"), pick_number: 3})
      ]

      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)
      assert stats.upserted == 3

      assert find_pick(@repo, :majors, Decimal.new("1.0"), team_a.id, @major_season) != nil
      assert find_pick(@repo, :high, Decimal.new("1.0"), team_a.id, @minor_season) != nil
      assert find_pick(@repo, :low, Decimal.new("1.0"), team_a.id, @minor_season) != nil
    end

    test "inserts picks for multiple teams", %{team_a: team_a, team_b: team_b} do
      picks = [
        parsed_pick(%{original_owner_csv: "Alpha", current_owner_csv: "Alpha", pick_number: 10}),
        parsed_pick(%{original_owner_csv: "Beta", current_owner_csv: "Beta", pick_number: 20})
      ]

      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)
      assert stats.upserted == 2

      assert find_pick(@repo, :majors, Decimal.new("1.0"), team_a.id, @major_season) != nil
      assert find_pick(@repo, :majors, Decimal.new("1.0"), team_b.id, @major_season) != nil
    end
  end

  describe "sync_from_sheet/2 - upserting existing picks" do
    test "updates currentOwnerId when a pick has been traded", %{
      team_a: team_a,
      team_b: team_b
    } do
      # Seed the DB: Alpha holds her own major league pick (season = @major_season)
      %DraftPick{}
      |> Ecto.Changeset.change(%{
        id: Ecto.UUID.generate(),
        type: :majors,
        round: Decimal.new("1.0"),
        season: @major_season,
        pick_number: 5,
        currentOwnerId: team_a.id,
        originalOwnerId: team_a.id,
        last_synced_at: ~U[2025-01-01 00:00:00.000000Z]
      })
      |> @repo.insert!()

      # Sheet now shows Alpha's pick in Beta's column (traded)
      picks = [
        parsed_pick(%{
          original_owner_csv: "Alpha",
          current_owner_csv: "Beta",
          pick_number: 5
        })
      ]

      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)
      assert stats.upserted == 1

      pick = find_pick(@repo, :majors, Decimal.new("1.0"), team_a.id, @major_season)
      assert pick.currentOwnerId == team_b.id
      assert pick.originalOwnerId == team_a.id
    end

    test "updates pick_number on upsert", %{team_a: team_a} do
      %DraftPick{}
      |> Ecto.Changeset.change(%{
        id: Ecto.UUID.generate(),
        type: :majors,
        round: Decimal.new("2.0"),
        season: @major_season,
        pick_number: 99,
        currentOwnerId: team_a.id,
        originalOwnerId: team_a.id,
        last_synced_at: ~U[2025-01-01 00:00:00.000000Z]
      })
      |> @repo.insert!()

      picks = [parsed_pick(%{round: Decimal.new("2.0"), pick_number: 42})]
      {:ok, _stats} = Sync.sync_from_sheet(picks, @repo)

      pick = find_pick(@repo, :majors, Decimal.new("2.0"), team_a.id, @major_season)
      assert pick.pick_number == 42
    end

    test "updates last_synced_at on every upsert", %{team_a: team_a} do
      old_time = ~U[2025-01-01 00:00:00.000000Z]

      %DraftPick{}
      |> Ecto.Changeset.change(%{
        id: Ecto.UUID.generate(),
        type: :majors,
        round: Decimal.new("1.0"),
        season: @major_season,
        pick_number: 5,
        currentOwnerId: team_a.id,
        originalOwnerId: team_a.id,
        last_synced_at: old_time
      })
      |> @repo.insert!()

      picks = [parsed_pick()]
      {:ok, _stats} = Sync.sync_from_sheet(picks, @repo)

      pick = find_pick(@repo, :majors, Decimal.new("1.0"), team_a.id, @major_season)
      assert DateTime.compare(pick.last_synced_at, old_time) == :gt
    end

    test "updates an existing minor league pick using the minor season", %{team_a: team_a} do
      %DraftPick{}
      |> Ecto.Changeset.change(%{
        id: Ecto.UUID.generate(),
        type: :high,
        round: Decimal.new("1.0"),
        season: @minor_season,
        pick_number: 77,
        currentOwnerId: team_a.id,
        originalOwnerId: team_a.id,
        last_synced_at: ~U[2025-01-01 00:00:00.000000Z]
      })
      |> @repo.insert!()

      picks = [parsed_pick(%{type: :high, round: Decimal.new("1.0"), pick_number: 88})]
      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)
      assert stats.upserted == 1

      pick = find_pick(@repo, :high, Decimal.new("1.0"), team_a.id, @minor_season)
      assert pick.pick_number == 88
    end
  end

  describe "sync_from_sheet/2 - owner resolution" do
    test "skips picks whose original_owner_csv has no matching user" do
      picks = [parsed_pick(%{original_owner_csv: "UnknownUser"})]
      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)

      assert stats.skipped_no_owner == 1
      assert stats.upserted == 0
    end

    test "skips picks whose current_owner_csv has no matching user" do
      picks = [parsed_pick(%{current_owner_csv: "Ghost"})]
      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)

      assert stats.skipped_no_owner == 1
      assert stats.upserted == 0
    end

    test "counts both upserted and skipped in the same batch", %{team_a: _team_a} do
      picks = [
        parsed_pick(%{original_owner_csv: "Alpha", current_owner_csv: "Alpha"}),
        parsed_pick(%{original_owner_csv: "NoSuchPerson", round: Decimal.new("2.0")})
      ]

      {:ok, stats} = Sync.sync_from_sheet(picks, @repo)
      assert stats.upserted == 1
      assert stats.skipped_no_owner == 1
    end
  end

  describe "sync_from_sheet/2 - empty input" do
    test "returns zero stats and does not error on empty list" do
      {:ok, stats} = Sync.sync_from_sheet([], @repo)
      assert stats.upserted == 0
      assert stats.skipped_no_owner == 0
    end
  end

  describe "sync_from_sheet/2 - error handling" do
    test "returns {:error, exception} when resolve_season raises (all thresholds in future)" do
      Application.put_env(:trade_machine, :draft_picks_season_thresholds, [
        {~D[9999-01-01], 9999}
      ])

      result = Sync.sync_from_sheet([], @repo)

      assert {:error, %RuntimeError{}} = result
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_season/0
  # ---------------------------------------------------------------------------

  describe "resolve_season/1" do
    test "returns the minor league season for the first threshold on or before the reference date" do
      Application.put_env(:trade_machine, :draft_picks_season_thresholds, [
        {~D[2027-04-01], 2027},
        {~D[2026-03-25], 2026},
        {~D[2000-01-01], 2025}
      ])

      # Fixed date: after 2000-01-01 but before 2026-03-25 so we expect the 2025 bucket
      # (would fail on real "today" once calendar passes 2026-03-25).
      assert Sync.resolve_season(~D[2026-03-20]) == 2025
    end

    test "raises RuntimeError when the reference date precedes all thresholds" do
      Application.put_env(:trade_machine, :draft_picks_season_thresholds, [
        {~D[9999-01-01], 9999}
      ])

      assert_raise RuntimeError, ~r/No matching draft season/, fn ->
        Sync.resolve_season(~D[2000-01-01])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # build_owner_map/1
  # ---------------------------------------------------------------------------

  describe "build_owner_map/1" do
    test "returns a map of csv_name -> team_id for users with both set", %{
      team_a: team_a,
      team_b: team_b
    } do
      owner_map = Sync.build_owner_map(@repo)

      assert owner_map["Alpha"] == team_a.id
      assert owner_map["Beta"] == team_b.id
    end

    test "excludes users with nil csv_name", %{team_a: team_a} do
      insert_user!(@repo, %{csv_name: nil, teamId: team_a.id})
      owner_map = Sync.build_owner_map(@repo)
      # The map should only have entries where csv_name is not nil
      assert Enum.all?(Map.keys(owner_map), &(not is_nil(&1)))
    end
  end
end
