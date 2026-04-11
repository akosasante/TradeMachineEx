defmodule TradeMachine.Mailer.TradeSubmitEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias TradeMachine.Data.HydratedTrade
  alias TradeMachine.Data.User
  alias TradeMachine.Mailer.TradeSubmitEmail
  alias Swoosh.Email

  # ── Fixtures ──────────────────────────────────────────────────────────────

  defp build_user(attrs \\ %{}) do
    struct(
      User,
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          display_name: "Creator User",
          email: "creator@example.com",
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
          status: :accepted,
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

  # ── generate_email/4 tests ─────────────────────────────────────────────────

  describe "generate_email/4" do
    test "creates a valid Swoosh email struct" do
      trade = build_hydrated_trade()
      user = build_user()

      email =
        TradeSubmitEmail.generate_email(
          trade,
          user,
          "https://v3.example.com/trades/abc?action=submit&token=tok1",
          "staging"
        )

      assert %Email{} = email
    end

    test "sets subject to 'Your Trade is Ready to Submit'" do
      trade = build_hydrated_trade()
      user = build_user()

      email =
        TradeSubmitEmail.generate_email(trade, user, "https://submit.example.com", "staging")

      assert email.subject == "Your Trade is Ready to Submit"
    end

    test "sends from tradebot address" do
      email =
        TradeSubmitEmail.generate_email(
          build_hydrated_trade(),
          build_user(),
          "https://submit.example.com",
          "staging"
        )

      assert email.from == {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
    end

    test "sends to staging override email in non-production env" do
      user = build_user(%{email: "real@example.com"})
      staging_email = Application.get_env(:trade_machine, :staging_email)

      email =
        TradeSubmitEmail.generate_email(
          build_hydrated_trade(),
          user,
          "https://submit.example.com",
          "staging"
        )

      assert email.to == [{user.display_name, staging_email}]
    end

    test "sends to real user email in production" do
      user = build_user(%{email: "real@example.com", display_name: "Real Person"})

      email =
        TradeSubmitEmail.generate_email(
          build_hydrated_trade(),
          user,
          "https://submit.example.com",
          "production"
        )

      assert email.to == [{"Real Person", "real@example.com"}]
    end

    test "title names the single recipient when there is one" do
      trade = build_hydrated_trade(%{recipients: ["Team Beta"]})
      user = build_user()

      email =
        TradeSubmitEmail.generate_email(trade, user, "https://submit.example.com", "staging")

      assert String.contains?(email.html_body, "Team Beta accepted your trade proposal")
      assert String.contains?(email.text_body, "Team Beta accepted your trade proposal")
    end

    test "uses generic title when there are multiple recipients" do
      trade = build_hydrated_trade(%{recipients: ["Team Beta", "Team Gamma"]})
      user = build_user()

      email =
        TradeSubmitEmail.generate_email(trade, user, "https://submit.example.com", "staging")

      assert String.contains?(
               email.html_body,
               "All parties have accepted your trade proposal"
             )
    end

    test "includes submit_url CTA button in HTML and text body" do
      submit_url = "https://v3.example.com/trades/abc?action=submit&token=tok1"
      user = build_user()

      email = TradeSubmitEmail.generate_email(build_hydrated_trade(), user, submit_url, "staging")

      assert String.contains?(email.html_body, "Submit Trade")
      assert String.contains?(email.text_body, submit_url)
    end

    test "includes player names from traded_majors" do
      trade =
        build_hydrated_trade(%{
          traded_majors: [%{name: "Aaron Judge", sender: "Team Alpha", recipient: "Team Beta"}]
        })

      user = build_user()

      email =
        TradeSubmitEmail.generate_email(trade, user, "https://submit.example.com", "staging")

      assert String.contains?(email.html_body, "Aaron Judge")
      assert String.contains?(email.text_body, "Aaron Judge")
    end

    test "includes 'would receive' section for each team" do
      trade = build_hydrated_trade()
      user = build_user()

      email =
        TradeSubmitEmail.generate_email(trade, user, "https://submit.example.com", "staging")

      assert String.contains?(email.html_body, "Team Beta would receive:")
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

      email =
        TradeSubmitEmail.generate_email(trade, user, "https://submit.example.com", "staging")

      assert String.contains?(email.html_body, "Prospect Player")
      assert String.contains?(email.html_body, "Minors")
    end

    test "formats draft picks with ordinal round and type" do
      trade =
        build_hydrated_trade(%{
          traded_majors: [],
          traded_picks: [
            %{
              round: 3,
              type: "LOW",
              original_owner: "Team Alpha",
              sender: "Team Alpha",
              recipient: "Team Beta",
              season: 2025,
              owned_by: "Team Alpha"
            }
          ]
        })

      user = build_user()

      email =
        TradeSubmitEmail.generate_email(trade, user, "https://submit.example.com", "staging")

      assert String.contains?(email.html_body, "3rd round Low Minors pick")
      assert String.contains?(email.text_body, "3rd round Low Minors pick")
    end

    test "includes fallback link text below the button" do
      submit_url = "https://v3.example.com/trades/abc?action=submit&token=tok1"
      user = build_user()

      email = TradeSubmitEmail.generate_email(build_hydrated_trade(), user, submit_url, "staging")

      assert String.contains?(email.html_body, "If the button doesn't work")
      # HTML encodes & as &amp; in href attrs — check text body for the raw URL
      assert String.contains?(email.text_body, submit_url)
    end
  end

  # ── send/5 tests ───────────────────────────────────────────────────────────

  describe "send/5" do
    test "returns {:error, :not_found} when trade does not exist" do
      mock_repo = build_nil_repo()

      result =
        TradeSubmitEmail.send(
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          "https://submit.example.com",
          "staging",
          mock_repo
        )

      assert result == {:error, :not_found}
      refute_email_sent()
    end

    test "sends email successfully with V3 magic-link submit URL" do
      trade = build_hydrated_trade()
      user = build_user()
      mock_repo = build_mock_repo(trade, user)
      submit_url = "https://v3.example.com/trades/#{trade.trade_id}?action=submit&token=tok1"

      assert {:ok, _} =
               TradeSubmitEmail.send(
                 trade.trade_id,
                 user.id,
                 submit_url,
                 "production",
                 mock_repo
               )

      assert_email_sent(
        subject: "Your Trade is Ready to Submit",
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end

    test "sends email successfully with V2 submit URL" do
      trade = build_hydrated_trade()
      user = build_user()
      mock_repo = build_mock_repo(trade, user)
      submit_url = "https://v2.example.com/trade/#{trade.trade_id}/submit"

      assert {:ok, _} =
               TradeSubmitEmail.send(
                 trade.trade_id,
                 user.id,
                 submit_url,
                 "production",
                 mock_repo
               )

      assert_email_sent(subject: "Your Trade is Ready to Submit")
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
    def all(_query), do: []
    def all(_query, _opts), do: []
  end

  defmodule MockRepo do
    def one(_query), do: Process.get(:mock_trade)
    def get(_schema, _id), do: Process.get(:mock_user)
    def insert(%_{}), do: {:ok, nil}
    def all(_query), do: []
    def all(_query, _opts), do: []
  end
end
