defmodule TradeMachine.Discord.ActionDmTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.User
  alias TradeMachine.Discord.ActionDm

  # ── trade_not_found (repo stub — no DB) ────────────────────────────────────

  describe "send_trade_request_dm/5 — trade_not_found" do
    test "returns {:error, :trade_not_found} when hydrated trade is missing" do
      assert {:error, :trade_not_found} =
               ActionDm.send_trade_request_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://accept",
                 "http://decline",
                 __MODULE__.NilHydratedRepo
               )
    end
  end

  describe "send_trade_submit_dm/4 — trade_not_found" do
    test "returns {:error, :trade_not_found} when hydrated trade is missing" do
      assert {:error, :trade_not_found} =
               ActionDm.send_trade_submit_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "http://submit",
                 __MODULE__.NilHydratedRepo
               )
    end
  end

  describe "send_trade_declined_dm/5 — trade_not_found" do
    test "returns {:error, :trade_not_found} when hydrated trade is missing" do
      assert {:error, :trade_not_found} =
               ActionDm.send_trade_declined_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 true,
                 "http://view",
                 __MODULE__.NilHydratedRepo
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
      trade_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{id: "stub-dm-message-id"}} =
               ActionDm.send_trade_request_dm(
                 trade_id,
                 user_id,
                 "https://ex/accept",
                 "https://ex/decline",
                 full_mock_repo()
               )

      assert Process.get(:test_last_dm_discord_user_id) == "123456789"
      embed = Process.get(:test_last_dm_embed)
      assert embed.title == "Action Needed"
      assert is_list(embed.fields)
      assert hd(embed.fields).name =~ "Trade details"

      [row] = Process.get(:test_last_dm_components)
      assert row.type == 1
      [accept, decline] = row.components
      assert accept.url == "https://ex/accept"
      assert decline.url == "https://ex/decline"
    end

    test "includes trade item fields when hydrated trade has majors" do
      uid = Ecto.UUID.generate()
      tid = Ecto.UUID.generate()

      base = build_hydrated_trade()

      trade = %HydratedTrade{
        base
        | trade_id: tid,
          traded_majors: [
            %{name: "Star Player", sender: "Team A", recipient: "Team B"}
          ]
      }

      Process.put(:mock_hydrated_trade, trade)

      Process.put(
        :mock_user,
        struct(User, %{
          id: uid,
          display_name: "Mock",
          email: "mock@example.com",
          status: :active,
          role: :owner,
          discord_user_id: "999",
          user_settings: %{"notifications" => %{"tradeActionDiscordDm" => true}}
        })
      )

      assert {:ok, _} =
               ActionDm.send_trade_request_dm(
                 tid,
                 uid,
                 "https://a",
                 "https://d",
                 __MODULE__.TradeOnlyRepo
               )

      embed = Process.get(:test_last_dm_embed)
      assert Enum.any?(embed.fields, &(&1.name =~ "Team B"))
      assert Enum.any?(embed.fields, &(&1.value =~ "Star Player"))
    end
  end

  describe "send_trade_submit_dm/4 — happy path" do
    test "sends DM via stub when trade and user exist" do
      assert {:ok, %{id: "stub-dm-message-id"}} =
               ActionDm.send_trade_submit_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 "https://ex/submit",
                 full_mock_repo()
               )

      embed = Process.get(:test_last_dm_embed)
      assert embed.title == "Submit Your Trade"

      [row] = Process.get(:test_last_dm_components)
      assert hd(row.components).url == "https://ex/submit"
      assert hd(row.components).label == "Submit trade"
    end
  end

  describe "send_trade_declined_dm/5 — happy path" do
    test "sends DM via stub when trade and user exist" do
      assert {:ok, %{id: "stub-dm-message-id"}} =
               ActionDm.send_trade_declined_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 false,
                 "https://ex/view",
                 full_mock_repo()
               )

      [row] = Process.get(:test_last_dm_components)
      assert hd(row.components).url == "https://ex/view"
    end

    test "omits components when view_url is nil" do
      assert {:ok, _} =
               ActionDm.send_trade_declined_dm(
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 true,
                 nil,
                 full_mock_repo()
               )

      assert Process.get(:test_last_dm_components) == []
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

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

  @dm_enabled_settings %{"notifications" => %{"tradeActionDiscordDm" => true}}

  defp full_mock_repo do
    repo_with_user(%{discord_user_id: "123456789", user_settings: @dm_enabled_settings})
  end

  defmodule TradeOnlyRepo do
    @moduledoc false
    def one(query), do: one(query, [])
    def one(_query, _opts), do: Process.get(:mock_hydrated_trade)

    def get(schema, id), do: get(schema, id, [])
    def get(_schema, _id, _opts), do: Process.get(:mock_user)

    def all(_query), do: []
    def all(_query, _opts), do: []
  end

  defmodule NilHydratedRepo do
    @moduledoc false
    def one(query), do: one(query, [])
    def one(_query, _opts), do: nil

    def get(schema, id), do: get(schema, id, [])
    def get(_schema, _id, _opts), do: nil

    def all(_query), do: []
    def all(_query, _opts), do: []
  end
end
