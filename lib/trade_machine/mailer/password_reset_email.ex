defmodule TradeMachine.Mailer.PasswordResetEmail do
  use TradeMachine.Mailer

  alias TradeMachine.Data.User

  @spec send(User.t(), String.t()) :: {:ok, any()} | {:error, any()}
  def send(user = %User{}, frontend_environment) do
    generate_email(user, frontend_environment)
    |> do_deliver()
  end

  @spec send!(User.t(), String.t()) :: Swoosh.Email.t()
  def send!(user = %User{}, frontend_environment) do
    generate_email(user, frontend_environment)
    |> do_deliver!()
  end

  @spec generate_email(User.t(), String.t()) :: Swoosh.Email.t()
  def generate_email(user, frontend_environment) do
    user =
      if frontend_environment == "production" or frontend_environment == "development" do
        user
      else
        %User{user | email: Application.get_env(:trade_machine, :staging_email)}
      end

    new()
    |> from(from_tuple())
    |> to(user)
    |> subject("Password Reset Instructions")
    |> render_body(:password_reset, %{
      user: user,
      reset_url: build_reset_url(user, frontend_environment)
    })
  end

  defp build_reset_url(%User{password_reset_token: reset_token}, frontend_env) do
    "#{frontend_url(frontend_env)}/reset-password#token=#{reset_token}"
  end
end
