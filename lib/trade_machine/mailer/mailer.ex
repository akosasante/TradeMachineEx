defmodule TradeMachine.Mailer do
  use Swoosh.Mailer, otp_app: :trade_machine

  defmacro __using__(_opts) do
    quote do
      import Swoosh.Email
      import TradeMachine.Mailer, only: [from_email: 0, from_tuple: 0]
      use Phoenix.Swoosh, view: TradeMachine.Mailer.EmailView, layout: {TradeMachine.Mailer.EmailView, :email}

      @frontend_url Application.get_env(:trade_machine, :frontend_url, "http://localhost:3031")

      def do_deliver(%Swoosh.Email{} = email) do
        email
        |> Premailex.to_inline_css()
        |> TradeMachine.Mailer.deliver()
      end
    end
  end

  def from_email do
    Application.get_env(:trade_machine, __MODULE__)[:from_email]
  end

  def from_name do
    Application.get_env(:trade_machine, __MODULE__)[:from_name]
  end

  def from_tuple do
    {from_name(), from_email()}
  end
end
