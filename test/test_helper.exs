ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Production, :manual)
Ecto.Adapters.SQL.Sandbox.mode(TradeMachine.Repo.Staging, :manual)

# Helper module to set search_path for test schema
defmodule TestHelper do
  def set_search_path_for_sandbox(repo) do
    # Execute SET search_path after sandbox checkout
    Ecto.Adapters.SQL.query!(repo, "SET search_path TO test", [])
  end
end
