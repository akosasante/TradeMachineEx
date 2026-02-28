defmodule TradeMachine.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    # Use Ecto's prefix() function which returns the migration prefix
    # This is set by migration_default_prefix in the repo config
    migration_prefix = prefix() || "public"
    IO.puts("Running Oban migration up with prefix: #{migration_prefix}")
    Oban.Migration.up(version: 12, prefix: migration_prefix)
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    migration_prefix = prefix() || "public"
    Oban.Migration.down(version: 1, prefix: migration_prefix)
  end
end
