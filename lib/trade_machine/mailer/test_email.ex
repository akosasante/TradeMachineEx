defmodule TradeMachine.Mailer.TestEmail do
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
    |> subject("Test email from Flex Fox Fantasy League TradeMachine")
    |> render_body(:test, %{user: user})
  end
end
