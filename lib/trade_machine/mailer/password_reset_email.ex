 defmodule TradeMachine.Mailer.PasswordResetEmail do
  use TradeMachine.Mailer

  alias TradeMachine.Data.User

  @spec send(User.t()) :: {:ok, any()} | {:error, any()}
  def send(%User{} = user) do
    do_send(user)
    |> do_deliver()
  end

  @spec send!(User.t()) :: Swoosh.Email.t()
  def send!(%User{} = user) do
    do_send(user)
    |> TradeMachine.Mailer.deliver!()
  end

  @spec do_send(User.t()) :: Swoosh.Email.t()
  defp do_send(user) do
    new()
    |> from(from_tuple())
    |> to(user)
    |> subject("Password Reset Instructions")
    |> render_body(:password_reset, %{user: user, reset_url: build_reset_url(user)})
  end

  defp build_reset_url(%User{password_reset_token: reset_token}) do
    "#{@frontend_url}/reset_password#token=#{reset_token}"
  end
end