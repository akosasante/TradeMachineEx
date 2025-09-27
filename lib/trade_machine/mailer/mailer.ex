defmodule TradeMachine.Mailer do
  use Swoosh.Mailer, otp_app: :trade_machine

  def from_email do
    Application.get_env(:trade_machine, __MODULE__)[:from_email]
  end
end
