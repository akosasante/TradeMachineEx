defmodule TradeMachine.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    # Get the prefix from the repo's migration_default_prefix config
    prefix = repo_config(:migration_default_prefix) || "public"
    Oban.Migration.up(version: 12, prefix: prefix)
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    prefix = repo_config(:migration_default_prefix) || "public"
    Oban.Migration.down(version: 1, prefix: prefix)
  end

  defp repo_config(key) do
    repo = __MODULE__
    |> Module.split()
    |> Enum.take(2)
    |> Module.concat()
    
    Application.get_env(:trade_machine, repo)[key]
  end
end
