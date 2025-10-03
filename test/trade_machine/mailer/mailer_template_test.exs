defmodule TradeMachine.Mailer.MailerTemplateTest do
  use ExUnit.Case, async: true

  alias TradeMachine.Data.User
  alias TradeMachine.Mailer.PasswordResetEmail

  describe "email template rendering" do
    test "renders both HTML and text versions" do
      user = build_user()

      email = PasswordResetEmail.generate_email(user, "staging")

      # Both HTML and text bodies should be present and non-empty
      assert is_binary(email.html_body) and byte_size(email.html_body) > 0
      assert is_binary(email.text_body) and byte_size(email.text_body) > 0
    end

    test "HTML version includes layout with stadium background" do
      user = build_user()

      email = PasswordResetEmail.generate_email(user, "staging")

      # Should include layout elements
      assert String.contains?(email.html_body, "<!DOCTYPE html>")
      assert String.contains?(email.html_body, "email-header")
      # Baseball emoji
      assert String.contains?(email.html_body, "⚾")
    end

    test "text version is properly formatted" do
      user = build_user()

      email = PasswordResetEmail.generate_email(user, "staging")

      # Text version should be clean and readable
      assert String.contains?(email.text_body, "FlexFox Fantasy TradeMachine")
      # No HTML tags
      refute String.contains?(email.text_body, "<")
      # No HTML tags
      refute String.contains?(email.text_body, ">")
    end

    test "layout includes proper branding" do
      user = build_user()

      email = PasswordResetEmail.generate_email(user, "staging")

      # Check that layout elements are present
      assert String.contains?(email.html_body, "FlexFox Fantasy TradeMachine")
      assert String.contains?(email.text_body, "FlexFox Fantasy TradeMachine")

      # Check footer content
      assert String.contains?(
               email.text_body,
               "This email was sent from FlexFox Fantasy TradeMachine"
             )

      assert String.contains?(email.text_body, "reach out to league admins")
    end
  end

  # Helper function to build test users - reusable across mailer tests
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
