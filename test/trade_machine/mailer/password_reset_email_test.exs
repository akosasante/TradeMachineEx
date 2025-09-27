defmodule TradeMachine.Mailer.PasswordResetEmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias TradeMachine.Data.User
  alias TradeMachine.Mailer.PasswordResetEmail
  alias Swoosh.Email

  describe "generate_email/1" do
    test "creates email with proper metadata" do
      user = build_user()

      email = PasswordResetEmail.generate_email(user)

      assert %Email{} = email
      assert email.subject == "Password Reset Instructions"
      assert email.from == {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      assert email.to == [{"Test User", "test@example.com"}]
    end

    test "includes reset URL in email body" do
      user = build_user(%{password_reset_token: "test-token-123"})

      email = PasswordResetEmail.generate_email(user)

      # Check HTML body contains reset URL
      assert String.contains?(email.html_body, "http://localhost:3031/reset_password#token=test-token-123")

      # Check text body contains reset URL
      assert String.contains?(email.text_body, "http://localhost:3031/reset_password#token=test-token-123")
    end

    test "includes user display name in email content" do
      user = build_user(%{display_name: "John Doe"})

      email = PasswordResetEmail.generate_email(user)

      # Both HTML and text should contain the user's name
      assert String.contains?(email.html_body, "Hello John Doe,")
      assert String.contains?(email.text_body, "Hello John Doe,")
    end

    test "falls back to email when display_name is nil" do
      user = build_user(%{display_name: nil, email: "fallback@example.com"})

      email = PasswordResetEmail.generate_email(user)

      # Should use email as fallback
      assert String.contains?(email.html_body, "Hello fallback@example.com,")
      assert String.contains?(email.text_body, "Hello fallback@example.com,")
    end

    test "includes security information in email" do
      user = build_user()

      email = PasswordResetEmail.generate_email(user)

      # Check for security messaging
      assert String.contains?(email.html_body, "expire in 1 hour")
      assert String.contains?(email.text_body, "expire in 1 hour")
      assert String.contains?(email.html_body, "didn't request a password reset")
      assert String.contains?(email.text_body, "didn't request a password reset")
    end

    test "includes clickable button in HTML email" do
      user = build_user(%{password_reset_token: "test-token"})

      email = PasswordResetEmail.generate_email(user)

      # Check for button element in HTML
      assert String.contains?(email.html_body, ~s{class="button"})
      assert String.contains?(email.html_body, "Reset Password")

      # Check for fallback link
      assert String.contains?(email.html_body, ~s{class="fallback-link"})
    end

    test "includes proper branding elements" do
      user = build_user()

      email = PasswordResetEmail.generate_email(user)

      # Check for FlexFox Fantasy TradeMachine branding
      assert String.contains?(email.html_body, "FlexFox Fantasy TradeMachine")
      assert String.contains?(email.text_body, "FlexFox Fantasy TradeMachine")

      # Check for team signature
      assert String.contains?(email.html_body, "The TradeMachine Team")
      assert String.contains?(email.text_body, "The TradeMachine Team")
    end
  end

  describe "send/1" do
    test "successfully sends password reset email" do
      user = build_user()

      assert {:ok, _email} = PasswordResetEmail.send(user)

      # Assert email was sent using Swoosh TestAssertions
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )
    end

  end

  describe "send!/1" do
    test "successfully sends password reset email" do
      user = build_user()

      # send!/1 calls do_deliver!/1 which may return different values
      # depending on the adapter implementation
      result = PasswordResetEmail.send!(user)

      # The main thing is that the email gets sent
      assert_email_sent(
        subject: "Password Reset Instructions",
        to: [{"Test User", "test@example.com"}],
        from: {"FlexFox Fantasy TradeMachine", "tradebot@flexfoxfantasy.com"}
      )

      # For test adapter, result might be empty map or other value
      # The important part is that the email was delivered
      assert result != nil
    end
  end

  describe "build_reset_url/1" do
    test "generates correct reset URL with token" do
      user = build_user(%{password_reset_token: "abc123"})

      # Access private function via generate_email since build_reset_url is private
      email = PasswordResetEmail.generate_email(user)

      expected_url = "http://localhost:3031/reset_password#token=abc123"
      assert String.contains?(email.html_body, expected_url)
      assert String.contains?(email.text_body, expected_url)
    end

    test "uses frontend_url from config" do
      user = build_user(%{password_reset_token: "test-token"})

      # The URL should use the configured frontend URL
      email = PasswordResetEmail.generate_email(user)

      assert String.contains?(email.html_body, "http://localhost:3031/reset_password")
      assert String.contains?(email.text_body, "http://localhost:3031/reset_password")
    end
  end


  # Helper function to build test users
  defp build_user(attrs \\ %{}) do
    default_attrs = %{
      id: Ecto.UUID.generate(),
      display_name: "Test User",
      email: "test@example.com",
      password_reset_token: "sample-token-123",
      status: :active,
      role: :admin
    }

    struct(User, Map.merge(default_attrs, attrs))
  end
end