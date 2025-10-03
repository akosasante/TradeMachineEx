defmodule TradeMachine.Mailer.TestEmail do
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
      if frontend_environment == "production" do
        user
      else
        %User{user | email: Application.get_env(:trade_machine, :staging_email)}
      end

    new()
    |> from(from_tuple())
    |> to(user)
    |> subject("Test email from Flex Fox Fantasy League TradeMachine")
    |> render_body(:test, %{user: user})
  end
end
