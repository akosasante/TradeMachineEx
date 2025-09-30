defmodule TradeMachine.Mailer.RegistrationEmail do
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
    |> subject("You have been invited to register on FFF Trade Machine")
    |> render_body(:registration, %{user: user, registration_url: build_registration_url()})
  end

  defp build_registration_url do
    "#{frontend_url()}/register"
  end
end
