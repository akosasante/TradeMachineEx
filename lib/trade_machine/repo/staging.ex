defmodule TradeMachine.Repo.Staging do
  @moduledoc """
  Ecto repository for the staging database.

  Connects to PostgreSQL on port 5435 with the staging schema.
  Used for staging environment data operations and testing.
  """

  use Ecto.Repo,
    otp_app: :trade_machine,
    adapter: Ecto.Adapters.Postgres
end
