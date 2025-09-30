defmodule TradeMachine.Mailer.RegistrationEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias TradeMachine.Data.User
  alias TradeMachine.Mailer.RegistrationEmail
  alias Swoosh.Email

  describe "generate_email/1" do
    test "creates email with proper metadata" do
      user = build_user()

      email = RegistrationEmail.generate_email(user)

      assert %Email{} = email
      assert email.subject == "You have been invited to register on FFF Trade Machine"
      assert email.from == {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      assert email.to == [{"Test User", "test@example.com"}]
    end

    test "includes registration URL in email body" do
      user = build_user()

      email = RegistrationEmail.generate_email(user)

      expected_url = "http://localhost:3031/register"

      # Check HTML body contains registration URL
      assert String.contains?(email.html_body, expected_url)

      # Check text body contains registration URL
      assert String.contains?(email.text_body, expected_url)
    end

    test "includes user display name in email content" do
      user = build_user(%{display_name: "John Doe"})

      email = RegistrationEmail.generate_email(user)

      # Both HTML and text should contain the user's name
      assert String.contains?(email.html_body, "Hi John Doe,")
      assert String.contains?(email.text_body, "Hi John Doe,")
    end

    test "falls back to email when display_name is nil" do
      user = build_user(%{display_name: nil, email: "fallback@example.com"})

      email = RegistrationEmail.generate_email(user)

      # Should use email as fallback
      assert String.contains?(email.html_body, "Hi fallback@example.com,")
      assert String.contains?(email.text_body, "Hi fallback@example.com,")
    end

    test "includes invitation message in email" do
      user = build_user()

      email = RegistrationEmail.generate_email(user)

      # Check for invitation messaging
      assert String.contains?(email.html_body, "invited to register")
      assert String.contains?(email.text_body, "invited to register")
      assert String.contains?(email.html_body, "Flex Fox Fantasy Baseball League")
      assert String.contains?(email.text_body, "Flex Fox Fantasy Baseball League")
    end

    test "includes clickable register button in HTML email" do
      user = build_user()

      email = RegistrationEmail.generate_email(user)

      # Check for button element in HTML
      assert String.contains?(email.html_body, ~s{class="button"})
      assert String.contains?(email.html_body, "Register")

      # Check for fallback link
      assert String.contains?(email.html_body, ~s{class="registration-link"})
    end

    test "includes welcome message and proper branding" do
      user = build_user()

      email = RegistrationEmail.generate_email(user)

      # Check for welcome message
      assert String.contains?(email.html_body, "Welcome to the Flex Fox Fantasy League")
      assert String.contains?(email.text_body, "Welcome to the Flex Fox Fantasy League")

      # Check for FlexFox Fantasy TradeMachine branding
      assert String.contains?(email.html_body, "FlexFox Fantasy TradeMachine")
      assert String.contains?(email.text_body, "FlexFox Fantasy TradeMachine")

      # Check for team signature
      assert String.contains?(email.html_body, "The TradeMachine Team")
      assert String.contains?(email.text_body, "The TradeMachine Team")
    end
  end

  describe "send/1" do
    test "successfully sends registration email" do
      user = build_user()

      assert {:ok, _email} = RegistrationEmail.send(user)

      # Assert email was sent using Swoosh TestAssertions
      assert_email_sent(
        subject: "You have been invited to register on FFF Trade Machine",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end
  end

  describe "send!/1" do
    test "successfully sends registration email" do
      user = build_user()

      # send!/1 calls do_deliver!/1 which may return different values
      # depending on the adapter implementation
      result = RegistrationEmail.send!(user)

      # The main thing is that the email gets sent
      assert_email_sent(
        subject: "You have been invited to register on FFF Trade Machine",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )

      # For test adapter, result might be empty map or other value
      # The important part is that the email was delivered
      assert result != nil
    end
  end

  describe "build_registration_url/1" do
    test "generates correct registration URL" do
      user = build_user()

      # Access private function via generate_email since build_registration_url is private
      email = RegistrationEmail.generate_email(user)

      expected_url = "http://localhost:3031/register"
      assert String.contains?(email.html_body, expected_url)
      assert String.contains?(email.text_body, expected_url)
    end

    test "uses frontend_url from config" do
      user = build_user()

      # The URL should use the configured frontend URL
      email = RegistrationEmail.generate_email(user)

      assert String.contains?(email.html_body, "http://localhost:3031/register")
      assert String.contains?(email.text_body, "http://localhost:3031/register")
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
