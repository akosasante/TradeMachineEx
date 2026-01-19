defmodule TradeMachine.Repo.Production do
  @moduledoc """
  Ecto repository for the production database.

  Connects to PostgreSQL on port 5432 with the public schema.
  Used for production data operations and Oban job persistence.
  """

  use Ecto.Repo,
    otp_app: :trade_machine,
    adapter: Ecto.Adapters.Postgres
end
