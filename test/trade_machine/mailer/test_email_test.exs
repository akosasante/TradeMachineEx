defmodule TradeMachine.Mailer.TestEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias TradeMachine.Data.User
  alias TradeMachine.Mailer.TestEmail
  alias Swoosh.Email

  describe "generate_email/1" do
    test "creates email with proper metadata" do
      user = build_user()

      email = TestEmail.generate_email(user)

      assert %Email{} = email
      assert email.subject == "Test email from Flex Fox Fantasy League TradeMachine"
      assert email.from == {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      assert email.to == [{"Test User", "test@example.com"}]
    end

    test "includes user display name in email content" do
      user = build_user(%{display_name: "John Doe"})

      email = TestEmail.generate_email(user)

      # Both HTML and text should contain the user's name
      assert String.contains?(email.html_body, "Hi John Doe,")
      assert String.contains?(email.text_body, "Hi John Doe,")
    end

    test "falls back to email when display_name is nil" do
      user = build_user(%{display_name: nil, email: "fallback@example.com"})

      email = TestEmail.generate_email(user)

      # Should use email as fallback
      assert String.contains?(email.html_body, "Hi fallback@example.com,")
      assert String.contains?(email.text_body, "Hi fallback@example.com,")
    end

    test "includes test message content" do
      user = build_user()

      email = TestEmail.generate_email(user)

      # Check for test messaging
      assert String.contains?(email.html_body, "Testing... Testing...")
      assert String.contains?(email.text_body, "Testing... Testing...")
      assert String.contains?(email.html_body, "test email from the FlexFox Fantasy TradeMachine")
      assert String.contains?(email.text_body, "test email from the FlexFox Fantasy TradeMachine")
    end

    test "includes success confirmation message in HTML" do
      user = build_user()

      email = TestEmail.generate_email(user)

      # Check for success confirmation in HTML (with emoji)
      assert String.contains?(email.html_body, "email system is working correctly!")
      assert String.contains?(email.html_body, "🎉")
    end

    test "includes success confirmation message in text" do
      user = build_user()

      email = TestEmail.generate_email(user)

      # Check for success confirmation in text (without emoji)
      assert String.contains?(email.text_body, "email system is working correctly!")
      # Text version should not have emoji
      refute String.contains?(email.text_body, "🎉")
    end

    test "includes proper branding elements" do
      user = build_user()

      email = TestEmail.generate_email(user)

      # Check for FlexFox Fantasy TradeMachine branding
      assert String.contains?(email.html_body, "FlexFox Fantasy TradeMachine")
      assert String.contains?(email.text_body, "FlexFox Fantasy TradeMachine")

      # Check for team signature
      assert String.contains?(email.html_body, "The TradeMachine Team")
      assert String.contains?(email.text_body, "The TradeMachine Team")
    end
  end

  describe "send/1" do
    test "successfully sends test email" do
      user = build_user()

      assert {:ok, _email} = TestEmail.send(user)

      # Assert email was sent using Swoosh TestAssertions
      assert_email_sent(
        subject: "Test email from Flex Fox Fantasy League TradeMachine",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end
  end

  describe "send!/1" do
    test "successfully sends test email" do
      user = build_user()

      # send!/1 calls do_deliver!/1 which may return different values
      # depending on the adapter implementation
      result = TestEmail.send!(user)

      # The main thing is that the email gets sent
      assert_email_sent(
        subject: "Test email from Flex Fox Fantasy League TradeMachine",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )

      # For test adapter, result might be empty map or other value
      # The important part is that the email was delivered
      assert result != nil
    end
  end

  # Helper function to build test users
  defp build_user(attrs \\ %{}) do
    default_attrs = %{
      id: Ecto.UUID.generate(),
      display_name: "Test User",
      email: "test@example.com",
      status: :active,
      role: :admin
    }

    struct(User, Map.merge(default_attrs, attrs))
  end
end
