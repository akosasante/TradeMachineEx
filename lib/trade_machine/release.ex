defmodule TradeMachine.Release do
  @moduledoc """
  Release tasks for running migrations and other deployment-related operations.

  These functions are designed to be called via `bin/trade_machine eval` in production.
  """

  @app :trade_machine

  require Logger

  @doc """
  Runs migrations for a specific repo.

  ## Examples

      # Migrate production database
      /app/bin/trade_machine eval "TradeMachine.Release.migrate(TradeMachine.Repo.Production)"

      # Migrate staging database
      /app/bin/trade_machine eval "TradeMachine.Release.migrate(TradeMachine.Repo.Staging)"
  """
  def migrate(repo) do
    Logger.info("Running migrations for #{inspect(repo)}")

    load_app()

    for repo <- repos(repo) do
      # Log repo configuration for debugging
      config = Application.get_env(:trade_machine, repo)
      Logger.info("Repo config: #{inspect(config)}")

      # Get the migrations path
      migrations_path = get_migrations_path(repo)

      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo_instance ->
          # Get the prefix from repo config
          prefix = config[:migration_default_prefix] || "public"

          # Check what migrations Ecto sees
          migrations = Ecto.Migrator.migrations(repo_instance, migrations_path)
          Logger.info("Migrations status for #{inspect(repo)}: #{inspect(migrations)}")

          # Run migrations with explicit prefix option
          Ecto.Migrator.run(repo_instance, migrations_path, :up, all: true, prefix: prefix)
        end)
    end

    Logger.info("Migrations completed successfully for #{inspect(repo)}")
  end

  @doc """
  Runs migrations for all configured repos (Production and Staging).

  ## Examples

      /app/bin/trade_machine eval "TradeMachine.Release.migrate_all()"
  """
  def migrate_all do
    Logger.info("Running migrations for all repos")

    load_app()

    repos = [TradeMachine.Repo.Production, TradeMachine.Repo.Staging]

    for repo <- repos do
      Logger.info("Migrating #{inspect(repo)}")
      migrations_path = get_migrations_path(repo)
      config = Application.get_env(:trade_machine, repo)
      prefix = config[:migration_default_prefix] || "public"

      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, migrations_path, :up, all: true, prefix: prefix)
        )
    end

    Logger.info("All migrations completed successfully")
  end

  @doc """
  Rolls back the last migration for a specific repo.

  ## Examples

      /app/bin/trade_machine eval "TradeMachine.Release.rollback(TradeMachine.Repo.Production)"
  """
  def rollback(repo, step \\ 1) do
    Logger.info("Rolling back #{step} migration(s) for #{inspect(repo)}")

    load_app()

    for repo <- repos(repo) do
      migrations_path = get_migrations_path(repo)
      config = Application.get_env(:trade_machine, repo)
      prefix = config[:migration_default_prefix] || "public"

      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, migrations_path, :down, step: step, prefix: prefix)
        )
    end

    Logger.info("Rollback completed for #{inspect(repo)}")
  end

  defp repos(repo) when is_atom(repo), do: [repo]
  defp repos(repos) when is_list(repos), do: repos

  defp load_app do
    Application.load(@app)
  end

  defp get_migrations_path(repo) do
    # In releases, priv directory is under lib/APP_NAME-VERSION/priv
    # Try to find it dynamically
    app_dir = Application.app_dir(@app, "priv/repo/migrations")

    if File.dir?(app_dir) do
      app_dir
    else
      # Fallback to relative path (for development)
      "priv/repo/migrations"
    end
  end
end
