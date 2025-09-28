defmodule TradeMachine.Mailer.PasswordResetEmail do
  use TradeMachine.Mailer

  alias TradeMachine.Data.User

  @spec send(User.t()) :: {:ok, any()} | {:error, any()}
  def send(user = %User{}) do
    generate_email(user)
    |> do_deliver()
  end

  @spec send!(User.t()) :: Swoosh.Email.t()
  def send!(user = %User{}) do
    generate_email(user)
    |> do_deliver!()
  end

  @spec generate_email(User.t()) :: Swoosh.Email.t()
  def generate_email(user) do
    new()
    |> from(from_tuple())
    |> to(user)
    |> subject("Password Reset Instructions")
    |> render_body(:password_reset, %{user: user, reset_url: build_reset_url(user)})
  end

  defp build_reset_url(%User{password_reset_token: reset_token}) do
    "#{frontend_url()}/reset_password#token=#{reset_token}"
  end
end
