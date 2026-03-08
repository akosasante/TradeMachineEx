defmodule TradeMachine.Data.UserTest do
  use ExUnit.Case, async: false

  alias TradeMachine.Data.Team
  alias TradeMachine.Data.User

  @repo TradeMachine.Repo.Production

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(@repo)
    TestHelper.set_search_path_for_sandbox(@repo)
    :ok
  end

  defp insert_team!(attrs \\ %{}) do
    defaults = %{id: Ecto.UUID.generate(), name: "Test Team", status: :active}
    %Team{} |> Ecto.Changeset.change(Map.merge(defaults, attrs)) |> @repo.insert!()
  end

  defp insert_user!(attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      display_name: "Test User",
      email: "user-#{System.unique_integer([:positive])}@example.com",
      status: :active,
      role: :owner
    }

    %User{} |> Ecto.Changeset.change(Map.merge(defaults, attrs)) |> @repo.insert!()
  end

  describe "changeset/2" do
    test "returns a changeset for a user struct" do
      changeset = User.changeset(%User{}, %{})
      assert %Ecto.Changeset{} = changeset
    end

    test "can be called with defaults" do
      changeset = User.changeset()
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "get_by_id/2" do
    test "returns user when found" do
      user = insert_user!()
      result = User.get_by_id(user.id, @repo)
      assert result != nil
      assert result.id == user.id
    end

    test "returns nil when user is not found" do
      result = User.get_by_id(Ecto.UUID.generate(), @repo)
      assert result == nil
    end
  end

  describe "get_by_id_with_password_reset_token/2" do
    test "returns user with password_reset_token field loaded" do
      user = insert_user!(%{password_reset_token: "token-abc"})
      result = User.get_by_id_with_password_reset_token(user.id, @repo)
      assert result != nil
      assert result.id == user.id
      assert result.password_reset_token == "token-abc"
    end

    test "returns nil when user not found" do
      result = User.get_by_id_with_password_reset_token(Ecto.UUID.generate(), @repo)
      assert result == nil
    end

    test "uses default Production repo when no repo argument given" do
      result = User.get_by_id_with_password_reset_token(Ecto.UUID.generate())
      assert result == nil
    end
  end

  describe "get_user_by_csv_name/2" do
    test "returns user when csv_name matches" do
      insert_user!(%{csv_name: "Flexman"})
      result = User.get_user_by_csv_name("Flexman", @repo)
      assert result != nil
      assert result.csv_name == "Flexman"
    end

    test "returns nil when no user has that csv_name" do
      result = User.get_user_by_csv_name("NoSuchOwner", @repo)
      assert result == nil
    end
  end

  describe "get_user_team_id/2" do
    test "returns teamId when user with matching email has a team" do
      team = insert_team!()
      insert_user!(%{email: "owner@example.com", teamId: team.id})

      result = User.get_user_team_id([email: "owner@example.com"], @repo)
      assert result == team.id
    end

    test "returns nil when user is not found" do
      result = User.get_user_team_id([email: "nobody@example.com"], @repo)
      assert result == nil
    end

    test "uses default Production repo when no repo argument given" do
      result = User.get_user_team_id(email: "nonexistent-default@example.com")
      assert result == nil
    end
  end
end
