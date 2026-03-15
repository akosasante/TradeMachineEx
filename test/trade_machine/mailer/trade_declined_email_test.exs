defmodule TradeMachine.Mailer.TradeDeclinedEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.User
  alias TradeMachine.Mailer.TradeDeclinedEmail
  alias Swoosh.Email

  # ── Fixtures ──────────────────────────────────────────────────────────────

  defp build_user(attrs \\ %{}) do
    struct(
      User,
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          display_name: "Recipient User",
          email: "recipient@example.com",
          status: :active,
          role: :owner
        },
        attrs
      )
    )
  end

  defp build_hydrated_trade(attrs \\ %{}) do
    struct(
      HydratedTrade,
      Map.merge(
        %{
          trade_id: Ecto.UUID.generate(),
          status: :rejected,
          creator: "Team Alpha",
          recipients: ["Team Beta"],
          declined_by: "Team Beta",
          declined_reason: "Not interested at this time",
          traded_majors: [
            %{
              name: "Aaron Judge",
              sender: "Team Alpha",
              recipient: "Team Beta",
              league: "MAJORS",
              main_position: "RF",
              mlb_team: "NYY"
            }
          ],
          traded_minors: [],
          traded_picks: []
        },
        attrs
      )
    )
  end

  # ── generate_email/6 tests ─────────────────────────────────────────────────

  describe "generate_email/6" do
    test "creates a valid Swoosh email struct" do
      trade = build_hydrated_trade()
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      assert %Email{} = email
    end

    test "sets subject to 'Trade Declined'" do
      trade = build_hydrated_trade()
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, false, nil, "staging")

      assert email.subject == "Trade Declined"
    end

    test "sends from tradebot address" do
      email =
        TradeDeclinedEmail.generate_email(
          build_hydrated_trade(),
          build_user(),
          false,
          nil,
          "staging"
        )

      assert email.from == {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
    end

    test "sends to staging override email in non-production env" do
      user = build_user(%{email: "real@example.com"})
      staging_email = Application.get_env(:trade_machine, :staging_email)

      email =
        TradeDeclinedEmail.generate_email(build_hydrated_trade(), user, false, nil, "staging")

      assert email.to == [{user.display_name, staging_email}]
    end

    test "sends to real user email in production" do
      user = build_user(%{email: "real@example.com", display_name: "Real Person"})

      email =
        TradeDeclinedEmail.generate_email(build_hydrated_trade(), user, false, nil, "production")

      assert email.to == [{"Real Person", "real@example.com"}]
    end

    test "uses personalized creator title when is_creator is true" do
      trade = build_hydrated_trade(%{declined_by: "Team Beta"})
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      assert String.contains?(
               email.html_body,
               "Your trade proposal was declined by Team Beta"
             )

      assert String.contains?(
               email.text_body,
               "Your trade proposal was declined by Team Beta"
             )
    end

    test "uses personalized recipient title when is_creator is false" do
      trade = build_hydrated_trade(%{declined_by: "Team Beta"})
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, false, nil, "staging")

      assert String.contains?(
               email.html_body,
               "A trade you were part of was declined by Team Beta"
             )

      assert String.contains?(
               email.text_body,
               "A trade you were part of was declined by Team Beta"
             )
    end

    test "includes decline reason in email body when present" do
      trade = build_hydrated_trade(%{declined_reason: "Not enough value"})
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      assert String.contains?(email.html_body, "Not enough value")
      assert String.contains?(email.text_body, "Not enough value")
    end

    test "omits reason section when declined_reason is nil" do
      trade = build_hydrated_trade(%{declined_reason: nil})
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      refute String.contains?(email.html_body, "Reason:")
    end

    test "includes declining team name in email body" do
      trade = build_hydrated_trade(%{declined_by: "Team Beta"})
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, false, nil, "staging")

      assert String.contains?(email.html_body, "Team Beta")
    end

    test "includes player names from traded_majors" do
      trade =
        build_hydrated_trade(%{
          traded_majors: [%{name: "Aaron Judge", sender: "Team Alpha", recipient: "Team Beta"}]
        })

      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      assert String.contains?(email.html_body, "Aaron Judge")
      assert String.contains?(email.text_body, "Aaron Judge")
    end

    test "includes 'would have received' section for each team" do
      trade = build_hydrated_trade()
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      assert String.contains?(email.html_body, "Team Beta would have received:")
    end

    test "includes traded_minors with (Minors) label" do
      trade =
        build_hydrated_trade(%{
          traded_majors: [],
          traded_minors: [
            %{name: "Prospect Player", sender: "Team Alpha", recipient: "Team Beta"}
          ]
        })

      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      assert String.contains?(email.html_body, "Prospect Player")
      assert String.contains?(email.html_body, "Minors")
    end

    test "formats draft picks with ordinal round and type" do
      trade =
        build_hydrated_trade(%{
          traded_majors: [],
          traded_picks: [
            %{
              round: 2,
              type: "HIGH",
              original_owner: "Team Alpha",
              sender: "Team Alpha",
              recipient: "Team Beta",
              season: 2025,
              owned_by: "Team Alpha"
            }
          ]
        })

      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      assert String.contains?(email.html_body, "2nd round High Minors pick")
      assert String.contains?(email.text_body, "2nd round High Minors pick")
    end

    test "includes V3 summary CTA button when decline_url is present" do
      trade = build_hydrated_trade()
      user = build_user()
      decline_url = "https://v3.example.com/trades/abc-123"

      email = TradeDeclinedEmail.generate_email(trade, user, true, decline_url, "staging")

      assert String.contains?(email.html_body, "View Trade Summary")
      assert String.contains?(email.text_body, decline_url)
    end

    test "omits CTA button when decline_url is nil (V2 mode)" do
      trade = build_hydrated_trade()
      user = build_user()

      email = TradeDeclinedEmail.generate_email(trade, user, true, nil, "staging")

      refute String.contains?(email.html_body, "View Trade Summary")
    end
  end

  # ── send/6 tests ───────────────────────────────────────────────────────────

  describe "send/6" do
    test "returns {:error, :not_found} when trade does not exist" do
      mock_repo = build_nil_repo()

      result =
        TradeDeclinedEmail.send(
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          true,
          nil,
          "staging",
          mock_repo
        )

      assert result == {:error, :not_found}
      refute_email_sent()
    end

    test "sends email successfully when trade and user are found (creator)" do
      trade = build_hydrated_trade()
      user = build_user()
      mock_repo = build_mock_repo(trade, user)

      assert {:ok, _} =
               TradeDeclinedEmail.send(
                 trade.trade_id,
                 user.id,
                 true,
                 nil,
                 "production",
                 mock_repo
               )

      assert_email_sent(
        subject: "Trade Declined",
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end

    test "sends email successfully when trade and user are found (recipient)" do
      trade = build_hydrated_trade()
      user = build_user()
      mock_repo = build_mock_repo(trade, user)

      assert {:ok, _} =
               TradeDeclinedEmail.send(
                 trade.trade_id,
                 user.id,
                 false,
                 "https://v3.example.com/trades/abc-123",
                 "production",
                 mock_repo
               )

      assert_email_sent(subject: "Trade Declined")
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp build_nil_repo, do: __MODULE__.NilRepo

  defp build_mock_repo(trade, user) do
    Process.put(:mock_trade, trade)
    Process.put(:mock_user, user)
    __MODULE__.MockRepo
  end

  defmodule NilRepo do
    def one(_query), do: nil
    def get(_schema, _id), do: nil
    def insert(%_{}), do: {:ok, nil}
  end

  defmodule MockRepo do
    def one(_query), do: Process.get(:mock_trade)
    def get(_schema, _id), do: Process.get(:mock_user)
    def insert(%_{}), do: {:ok, nil}
  end
end
