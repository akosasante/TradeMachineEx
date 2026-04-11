defmodule TradeMachine.Discord.ActionDmTest do
  use TradeMachine.DataCase, async: false

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.User
  alias TradeMachine.Discord.ActionDm

  @repo TradeMachine.Repo.Production

  # ── trade_not_found (real Sandbox DB — no view row exists) ────────────────

  describe "send_trade_request_dm/5 — trade_not_found" do
    test "returns {:error, :trade_not_found} for unknown trade_id" do
      user = insert_user!(%{discord_user_id: "123456789"})

      assert {:error, :trade_not_found} =
               ActionDm.send_trade_request_dm(
                 Ecto.UUID.generate(),
                 user.id,
                 "http://accept",
                 "http://decline",
                 @repo
               )
    end
  end

  describe "send_trade_submit_dm/4 — trade_not_found" do
    test "returns {:error, :trade_not_found} for unknown trade_id" do
      assert {:error, :trade_not_found} =
               ActionDm.send_trade_submit_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://submit",
                 @repo
               )
    end
  end

  describe "send_trade_declined_dm/5 — trade_not_found" do
    test "returns {:error, :trade_not_found} for unknown trade_id" do
      assert {:error, :trade_not_found} =
               ActionDm.send_trade_declined_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 true,
                 "http://view",
                 @repo
               )
    end
  end

  # ── user / discord_id errors (mock repo to supply a hydrated trade) ───────

  describe "send_trade_request_dm/5 — user errors" do
    test "returns {:error, :user_not_found} for unknown recipient" do
      assert {:error, :user_not_found} =
               ActionDm.send_trade_request_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://accept",
                 "http://decline",
                 repo_with_trade_only()
               )
    end

    test "returns {:error, :no_discord_user_id} when user has nil discord_user_id" do
      assert {:error, :no_discord_user_id} =
               ActionDm.send_trade_request_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://accept",
                 "http://decline",
                 repo_with_user(%{discord_user_id: nil})
               )
    end

    test "returns {:error, :no_discord_user_id} when user has blank discord_user_id" do
      assert {:error, :no_discord_user_id} =
               ActionDm.send_trade_request_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://accept",
                 "http://decline",
                 repo_with_user(%{discord_user_id: "  "})
               )
    end
  end

  # ── Happy path (mock repo — bypasses hydrated_trades view) ────────────────

  describe "send_trade_request_dm/5 — happy path" do
    test "sends DM via stub when trade and user exist" do
      assert {:ok, %{id: "stub-dm-message-id"}} =
               ActionDm.send_trade_request_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://accept",
                 "http://decline",
                 full_mock_repo()
               )
    end
  end

  describe "send_trade_submit_dm/4 — happy path" do
    test "sends DM via stub when trade and user exist" do
      assert {:ok, %{id: "stub-dm-message-id"}} =
               ActionDm.send_trade_submit_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://submit",
                 full_mock_repo()
               )
    end
  end

  describe "send_trade_declined_dm/5 — happy path" do
    test "sends DM via stub when trade and user exist" do
      assert {:ok, %{id: "stub-dm-message-id"}} =
               ActionDm.send_trade_declined_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 false,
                 "http://view",
                 full_mock_repo()
               )
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp insert_user!(attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      display_name: "Test User",
      email: "test-#{System.unique_integer([:positive])}@example.com",
      status: :active,
      role: :owner
    }

    params = Map.merge(defaults, attrs)
    %User{} |> Ecto.Changeset.change(params) |> @repo.insert!()
  end

  defp build_hydrated_trade do
    %HydratedTrade{
      trade_id: Ecto.UUID.generate(),
      status: :requested,
      creator: "Team Alpha",
      recipients: ["Team Beta"],
      declined_by: "Team Beta",
      traded_majors: [],
      traded_minors: [],
      traded_picks: []
    }
  end

  defp repo_with_trade_only do
    Process.put(:mock_hydrated_trade, build_hydrated_trade())
    Process.put(:mock_user, nil)
    __MODULE__.TradeOnlyRepo
  end

  defp repo_with_user(user_attrs) do
    Process.put(:mock_hydrated_trade, build_hydrated_trade())

    Process.put(
      :mock_user,
      struct(
        User,
        Map.merge(
          %{
            id: Ecto.UUID.generate(),
            display_name: "Mock User",
            email: "mock@example.com",
            status: :active,
            role: :owner
          },
          user_attrs
        )
      )
    )

    __MODULE__.TradeOnlyRepo
  end

  defp full_mock_repo do
    repo_with_user(%{discord_user_id: "123456789"})
  end

  defmodule TradeOnlyRepo do
    @moduledoc false
    def one(_query), do: Process.get(:mock_hydrated_trade)
    def get(_schema, _id), do: Process.get(:mock_user)
  end
end
