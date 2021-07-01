defmodule TradeMachine.Repo do
  use Ecto.Repo,
    otp_app: :trade_machine,
    adapter: Ecto.Adapters.Postgres
end
