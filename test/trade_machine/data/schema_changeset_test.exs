defmodule TradeMachine.Data.SchemaChangesetTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.Team
  alias TradeMachine.Data.Trade
  alias TradeMachine.Data.TradeItem
  alias TradeMachine.Data.TradeParticipant

  # NOTE: Trade.changeset/2 has cast_assoc calls for non-existent associations
  # (:traded_item_players, :traded_item_picks) and cannot be called without raising.
  # Coverage of those 2 lines is not achievable without refactoring the module.

  describe "DraftPick.changeset/2" do
    test "returns valid changeset with all required fields" do
      params = %{round: 1, season: 2025, type: :majors}
      changeset = DraftPick.changeset(%DraftPick{}, params)
      assert changeset.valid?
    end

    test "returns invalid changeset when required fields are missing" do
      changeset = DraftPick.changeset(%DraftPick{}, %{})
      refute changeset.valid?
      assert :round in Keyword.keys(changeset.errors)
      assert :season in Keyword.keys(changeset.errors)
      assert :type in Keyword.keys(changeset.errors)
    end

    test "accepts optional fields" do
      params = %{round: 1, season: 2025, type: :high, pick_number: 5}
      changeset = DraftPick.changeset(%DraftPick{}, params)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :pick_number) == 5
    end
  end

  describe "DraftPick.new/1" do
    test "returns a changeset struct" do
      changeset = DraftPick.new(%{round: 2, season: 2025, type: :low})
      assert changeset.valid?
    end

    test "returns invalid changeset for empty params" do
      changeset = DraftPick.new()
      refute changeset.valid?
    end
  end

  describe "Team.changeset/2" do
    test "returns a changeset for a team struct" do
      changeset = Team.changeset(%Team{}, %{name: "My Team"})
      assert %Ecto.Changeset{} = changeset
    end

    test "can be called with defaults" do
      changeset = Team.changeset()
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "Trade struct" do
    test "can be instantiated with basic fields" do
      trade = %Trade{status: :pending}
      assert trade.status == :pending
    end
  end

  describe "TradeItem.changeset/2" do
    test "returns a changeset for a trade item struct" do
      changeset = TradeItem.changeset(%TradeItem{}, %{trade_item_type: :player})
      assert %Ecto.Changeset{} = changeset
    end

    test "can be called with defaults" do
      changeset = TradeItem.changeset()
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "TradeParticipant.changeset/2" do
    test "returns a changeset for a trade participant struct" do
      changeset = TradeParticipant.changeset(%TradeParticipant{}, %{participant_type: :creator})
      assert %Ecto.Changeset{} = changeset
    end

    test "can be called with defaults" do
      changeset = TradeParticipant.changeset()
      assert %Ecto.Changeset{} = changeset
    end
  end
end
