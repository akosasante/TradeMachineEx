defmodule TradeMachine.Mailer.TradeRequestEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.User
  alias TradeMachine.Mailer.TradeRequestEmail
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
          status: :requested,
          creator: "Team Alpha",
          recipients: ["Team Beta"],
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

  # ── generate_email/5 tests ──────────────────────────────────────────────

  describe "generate_email/5" do
    test "creates a valid Swoosh email struct" do
      trade = build_hydrated_trade()
      user = build_user()

      email =
        TradeRequestEmail.generate_email(
          trade,
          user,
          "http://accept",
          "http://decline",
          "staging"
        )

      assert %Email{} = email
    end

    test "sets subject to 'Trade Proposal from {creator}'" do
      trade = build_hydrated_trade(%{creator: "Team Alpha"})
      user = build_user()

      email =
        TradeRequestEmail.generate_email(
          trade,
          user,
          "http://accept",
          "http://decline",
          "staging"
        )

      assert email.subject == "Trade Proposal from Team Alpha"
    end

    test "sends from tradebot address" do
      email =
        TradeRequestEmail.generate_email(
          build_hydrated_trade(),
          build_user(),
          "http://a",
          "http://d",
          "staging"
        )

      assert email.from == {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
    end

    test "sends to staging override email in non-production env" do
      user = build_user(%{email: "real@example.com"})
      staging_email = Application.get_env(:trade_machine, :staging_email)

      email =
        TradeRequestEmail.generate_email(
          build_hydrated_trade(),
          user,
          "http://a",
          "http://d",
          "staging"
        )

      assert email.to == [{user.display_name, staging_email}]
    end

    test "sends to real user email in production" do
      user = build_user(%{email: "real@example.com", display_name: "Real Person"})

      email =
        TradeRequestEmail.generate_email(
          build_hydrated_trade(),
          user,
          "http://a",
          "http://d",
          "production"
        )

      assert email.to == [{"Real Person", "real@example.com"}]
    end

    test "includes trade creator name in title_text for 2-team trade" do
      trade = build_hydrated_trade(%{creator: "Team Alpha", recipients: ["Team Beta"]})
      user = build_user()

      email = TradeRequestEmail.generate_email(trade, user, "http://a", "http://d", "staging")

      assert String.contains?(email.html_body, "Team Alpha requested a trade with you:")
      assert String.contains?(email.text_body, "Team Alpha requested a trade with you:")
    end

    test "uses multi-team title for 3+ team trade" do
      trade =
        build_hydrated_trade(%{creator: "Team Alpha", recipients: ["Team Beta", "Team Gamma"]})

      user = build_user()

      email = TradeRequestEmail.generate_email(trade, user, "http://a", "http://d", "staging")

      assert String.contains?(email.html_body, "Team Alpha requested a trade with you and others")
    end

    test "includes player names from traded_majors in email body" do
      trade =
        build_hydrated_trade(%{
          traded_majors: [
            %{name: "Aaron Judge", sender: "Team Alpha", recipient: "Team Beta"}
          ]
        })

      user = build_user()

      email = TradeRequestEmail.generate_email(trade, user, "http://a", "http://d", "staging")

      assert String.contains?(email.html_body, "Aaron Judge")
      assert String.contains?(email.text_body, "Aaron Judge")
    end

    test "includes 'would receive' section for each team" do
      trade = build_hydrated_trade()
      user = build_user()

      email = TradeRequestEmail.generate_email(trade, user, "http://a", "http://d", "staging")

      assert String.contains?(email.html_body, "Team Beta would receive:")
    end

    test "includes accept_url and decline_url in email body" do
      accept_url = "https://app.example.com/trades/abc?action=accept&token=tok1"
      decline_url = "https://app.example.com/trades/abc?action=decline&token=tok2"

      email =
        TradeRequestEmail.generate_email(
          build_hydrated_trade(),
          build_user(),
          accept_url,
          decline_url,
          "staging"
        )

      # HTML-encodes & as &amp; in href attributes — check text body for raw URLs
      assert String.contains?(email.text_body, accept_url)
      assert String.contains?(email.text_body, decline_url)

      # HTML body has the URL (HTML-encoded) — check for the distinctive token part
      assert String.contains?(email.html_body, "action=accept")
      assert String.contains?(email.html_body, "action=decline")
      assert String.contains?(email.html_body, "tok1")
      assert String.contains?(email.html_body, "tok2")
    end

    test "formats draft picks with ordinal round and type" do
      trade =
        build_hydrated_trade(%{
          traded_majors: [],
          traded_picks: [
            %{
              round: 1,
              type: "MAJORS",
              original_owner: "Team Alpha",
              sender: "Team Alpha",
              recipient: "Team Beta",
              season: 2025,
              owned_by: "Team Alpha"
            }
          ]
        })

      user = build_user()

      email = TradeRequestEmail.generate_email(trade, user, "http://a", "http://d", "staging")

      assert String.contains?(email.html_body, "1st round Majors pick")
      assert String.contains?(email.text_body, "1st round Majors pick")
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

      email = TradeRequestEmail.generate_email(trade, user, "http://a", "http://d", "staging")

      assert String.contains?(email.html_body, "Prospect Player")
      assert String.contains?(email.html_body, "Minors")
    end
  end

  # ── send/6 tests ──────────────────────────────────────────────────────────

  describe "send/6" do
    test "returns {:error, :not_found} when trade does not exist" do
      # Using a nil-returning mock repo
      mock_repo = build_nil_repo()

      result =
        TradeRequestEmail.send(
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          "http://a",
          "http://d",
          "staging",
          mock_repo
        )

      assert result == {:error, :not_found}
      refute_email_sent()
    end

    test "sends email successfully when trade and user are found" do
      trade = build_hydrated_trade()
      user = build_user()
      mock_repo = build_mock_repo(trade, user)

      assert {:ok, _} =
               TradeRequestEmail.send(
                 trade.trade_id,
                 user.id,
                 "http://accept",
                 "http://decline",
                 "production",
                 mock_repo
               )

      assert_email_sent(
        subject: "Trade Proposal from Team Alpha",
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # A minimal mock repo module that returns nil for all queries (trade/user not found)
  defp build_nil_repo do
    # We pass an anonymous function module-like map. Since we use repo.one/1 and repo.get/2
    # from HydratedTrade and User, we need a module with those functions.
    # Use a simple inline approach with Mox is preferred, but here we stub a behaviour.
    __MODULE__.NilRepo
  end

  # A mock repo that returns pre-built structs
  defp build_mock_repo(trade, user) do
    # Register mock data for the test process
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
