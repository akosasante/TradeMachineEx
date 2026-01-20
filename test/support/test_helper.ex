defmodule TestHelper do
  @moduledoc """
  Helper functions for test setup and configuration.
  """

  @doc """
  Sets the search_path to 'test' schema for a sandboxed database connection.

  This is necessary because the test environment uses the 'test' schema
  to isolate test data from production and staging schemas.
  """
  def set_search_path_for_sandbox(repo) do
    # Execute SET search_path after sandbox checkout
    Ecto.Adapters.SQL.query!(repo, "SET search_path TO test", [])
  end
end
