defmodule TradeMachine.Discord.TradesIntegrationTest do
  use TradeMachine.DataCase, async: false

  alias Decimal, as: D
  alias TradeMachine.Data.DraftPick
  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Team
  alias TradeMachine.Data.Trade
  alias TradeMachine.Data.TradeItem
  alias TradeMachine.Data.TradeParticipant
  alias TradeMachine.Data.User
  alias TradeMachine.Discord.CommandRouter
  alias TradeMachine.Discord.TradeListEmbedBuilder
  alias TradeMachine.Discord.Trades

  @repo TradeMachine.Repo.Production

  setup do
    team_a = insert_team!(@repo, %{name: "Discord Team A"})
    team_b = insert_team!(@repo, %{name: "Discord Team B"})

    discord_snowflake = System.unique_integer([:positive])
    discord_id = Integer.to_string(discord_snowflake)

    user_a =
      insert_user!(@repo, %{
        csv_name: "OwnerA",
        teamId: team_a.id,
        display_name: "Owner A",
        discord_user_id: discord_id
      })

    _user_b =
      insert_user!(@repo, %{
        csv_name: "OwnerB",
        teamId: team_b.id,
        display_name: "Owner B"
      })

    %{
      team_a: team_a,
      team_b: team_b,
      user_a: user_a,
      discord_id: discord_id,
      discord_snowflake: discord_snowflake
    }
  end

  describe "find_user_by_discord_id/2" do
    test "returns the linked user when present", %{discord_id: discord_id, user_a: user_a} do
      assert %User{id: id} = Trades.find_user_by_discord_id(discord_id, @repo)
      assert id == user_a.id
    end

    test "returns nil when not linked" do
      assert Trades.find_user_by_discord_id("no-such-discord", @repo) == nil
    end
  end

  describe "count_trades_for_team/2 and list_recent_trades_for_team/2" do
    test "respects status filter and limits to five trades", %{
      team_a: team_a,
      team_b: team_b
    } do
      player =
        insert_player!(@repo, %{
          name: "Listed Major",
          league: :major,
          leagueTeamId: team_a.id
        })

      for i <- 1..6 do
        trade =
          insert_trade!(@repo, %{
            status: if(rem(i, 2) == 0, do: :submitted, else: :requested)
          })

        insert_participant!(@repo, trade, team_a, :creator)
        insert_participant!(@repo, trade, team_b, :recipient)

        insert_trade_item_player!(@repo, trade, team_b.id, team_a.id, player.id)
      end

      active = [:requested, :pending, :accepted]

      assert Trades.count_trades_for_team(team_a.id, repo: @repo, statuses: active) == 3

      assert length(Trades.list_recent_trades_for_team(team_a.id, repo: @repo, statuses: active)) ==
               3

      assert Trades.count_trades_for_team(team_a.id, repo: @repo, statuses: nil) == 6

      listed = Trades.list_recent_trades_for_team(team_a.id, repo: @repo, statuses: nil)
      assert length(listed) == 5
      assert %Trade{} = hd(listed)
      assert Ecto.assoc_loaded?(hd(listed).participants)
      assert Ecto.assoc_loaded?(hd(listed).traded_items)
    end
  end

  describe "TradeListEmbedBuilder with preloaded trades" do
    test "shows You get / gets, player and pick labels, and view link", %{
      team_a: team_a,
      team_b: team_b
    } do
      player =
        insert_player!(@repo, %{
          name: "Embed Major Star",
          league: :major,
          leagueTeamId: team_a.id
        })

      pick =
        %DraftPick{}
        |> DraftPick.changeset(%{
          round: D.new(1),
          season: 2025,
          type: :majors,
          originalOwnerId: team_b.id
        })
        |> @repo.insert!()

      trade = insert_trade!(@repo, %{status: :pending})

      insert_participant!(@repo, trade, team_a, :creator)
      insert_participant!(@repo, trade, team_b, :recipient)

      insert_trade_item_player!(@repo, trade, team_b.id, team_a.id, player.id)

      %TradeItem{
        trade_id: trade.id,
        trade_item_type: :pick,
        trade_item_id: pick.id,
        senderId: team_b.id,
        recipientId: team_a.id
      }
      |> @repo.insert!()

      [loaded] =
        Trades.list_recent_trades_for_team(team_a.id, repo: @repo, statuses: nil)

      embed =
        TradeListEmbedBuilder.build(
          "Embed Title",
          [loaded],
          frontend_url: "https://app.example.test",
          repo: @repo,
          user_team_id: team_a.id,
          total_count: 1
        )

      assert embed.title == "Embed Title"
      assert embed.description =~ "You get"
      assert embed.description =~ "OwnerB"
      assert embed.description =~ "gets"
      assert embed.description =~ "1st"
      assert embed.description =~ "Major League"
      assert embed.description =~ "pick"
      assert embed.description =~ "https://app.example.test/trades/#{trade.id}/review"
      assert embed.footer.text =~ "View all trades at"
    end
  end

  describe "slash command handlers" do
    setup do
      prev = Application.get_env(:trade_machine, :frontend_url_production)
      Application.put_env(:trade_machine, :frontend_url_production, "https://app.example.test")

      on_exit(fn ->
        if prev == nil do
          Application.delete_env(:trade_machine, :frontend_url_production)
        else
          Application.put_env(:trade_machine, :frontend_url_production, prev)
        end
      end)

      :ok
    end

    test "my-trades command responds for unlinked Discord accounts" do
      interaction = %{
        data: %{name: "my-trades", options: nil},
        member: %{user_id: 9_999_888_777_666_555_444},
        token: "test-token",
        id: 1
      }

      assert CommandRouter.handle(interaction) == {:ok}
    end

    test "my-trades command responds for linked users with trades", %{
      discord_snowflake: snowflake,
      team_a: team_a,
      team_b: team_b
    } do
      player =
        insert_player!(@repo, %{
          name: "Cmd Major",
          league: :major,
          leagueTeamId: team_a.id
        })

      trade = insert_trade!(@repo, %{status: :requested})
      insert_participant!(@repo, trade, team_a, :creator)
      insert_participant!(@repo, trade, team_b, :recipient)
      insert_trade_item_player!(@repo, trade, team_b.id, team_a.id, player.id)

      interaction = %{
        data: %{name: "my-trades", options: nil},
        member: %{user_id: snowflake},
        token: "test-token",
        id: 1
      }

      assert CommandRouter.handle(interaction) == {:ok}
    end

    test "trade-history respects status option and linked user", %{
      discord_snowflake: snowflake,
      team_a: team_a,
      team_b: team_b
    } do
      trade = insert_trade!(@repo, %{status: :submitted})
      insert_participant!(@repo, trade, team_a, :creator)
      insert_participant!(@repo, trade, team_b, :recipient)

      interaction = %{
        data: %{
          name: "trade-history",
          options: [%{name: "status", value: "closed"}]
        },
        member: %{user_id: snowflake},
        token: "test-token",
        id: 1
      }

      assert CommandRouter.handle(interaction) == {:ok}
    end

    test "trade-history works when status option is omitted", %{
      discord_snowflake: snowflake,
      team_a: team_a,
      team_b: team_b
    } do
      trade = insert_trade!(@repo, %{status: :requested})
      insert_participant!(@repo, trade, team_a, :creator)
      insert_participant!(@repo, trade, team_b, :recipient)

      interaction = %{
        data: %{name: "trade-history", options: nil},
        member: %{user_id: snowflake},
        token: "test-token",
        id: 1
      }

      assert CommandRouter.handle(interaction) == {:ok}
    end
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
      name: "Player",
      league: :minor,
      mlb_team: nil,
      meta: nil,
      last_synced_at: nil,
      leagueTeamId: nil
    }

    params = Map.merge(defaults, attrs)
    %Player{} |> Ecto.Changeset.change(params) |> repo.insert!()
  end

  defp insert_trade!(repo, attrs) do
    defaults = %{status: :requested}
    params = Map.merge(defaults, attrs)
    %Trade{} |> Ecto.Changeset.change(params) |> repo.insert!()
  end

  defp insert_participant!(repo, trade, team, role) do
    %TradeParticipant{}
    |> Ecto.Changeset.change(%{
      participant_type: role,
      trade_id: trade.id,
      team_id: team.id
    })
    |> repo.insert!()
  end

  defp insert_trade_item_player!(repo, trade, sender_id, recipient_id, player_id) do
    %TradeItem{
      trade_id: trade.id,
      trade_item_type: :player,
      trade_item_id: player_id,
      senderId: sender_id,
      recipientId: recipient_id
    }
    |> repo.insert!()
  end
end
