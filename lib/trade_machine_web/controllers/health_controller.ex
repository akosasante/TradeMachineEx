defmodule TradeMachineWeb.HealthController do
  use TradeMachineWeb, :controller

  @moduledoc """
  Health check controller for container orchestration and monitoring.

  Provides endpoints for:
  - Basic health check (/health)
  - Readiness check (/ready)
  - Liveness check (/live)
  """

  def health(conn, _params) do
    status = perform_health_checks()

    case status.healthy do
      true ->
        conn
        |> put_status(200)
        |> json(status)

      false ->
        conn
        |> put_status(503)
        |> json(status)
    end
  end

  def ready(conn, _params) do
    # Readiness check - can the application serve requests?
    #    ready = database_ready?() && dependencies_ready?()
    ready = database_ready?()

    case ready do
      true ->
        conn
        |> put_status(200)
        |> json(%{status: "ready", timestamp: DateTime.utc_now()})

      false ->
        conn
        |> put_status(503)
        |> json(%{status: "not_ready", timestamp: DateTime.utc_now()})
    end
  end

  def live(conn, _params) do
    # Liveness check - is the application running?
    # This should be lightweight and just check if the app is responsive
    conn
    |> put_status(200)
    |> json(%{status: "alive", timestamp: DateTime.utc_now()})
  end

  defp perform_health_checks do
    checks = %{
      database: database_check(),
      oban: oban_check()
    }

    healthy = checks.database.healthy

    %{
      healthy: healthy,
      timestamp: DateTime.utc_now(),
      service: "trade_machine_ex",
      version: Application.spec(:trade_machine, :vsn) |> to_string(),
      checks: checks
    }
  end

  defp database_check do
    try do
      # Check both Production and Staging database connectivity
      prod_result =
        Ecto.Adapters.SQL.query(TradeMachine.Repo.Production, "SELECT 1", [], timeout: 5000)

      staging_result =
        Ecto.Adapters.SQL.query(TradeMachine.Repo.Staging, "SELECT 1", [], timeout: 5000)

      case {prod_result, staging_result} do
        {{:ok, _}, {:ok, _}} ->
          %{healthy: true, message: "Both Production and Staging database connections successful"}

        {{:error, error}, _} ->
          %{healthy: false, message: "Production database error: #{inspect(error)}"}

        {_, {:error, error}} ->
          %{healthy: false, message: "Staging database error: #{inspect(error)}"}
      end
    rescue
      error ->
        %{healthy: false, message: "Database exception: #{inspect(error)}"}
    end
  end

  @dialyzer {:nowarn_function, oban_check: 0}
  defp oban_check do
    prod_result = safe_check_queue(Oban.Production, :emails)
    staging_result = safe_check_queue(Oban.Staging, :emails)

    healthy = match?({:ok, :ok}, {prod_result, staging_result})

    message =
      case {prod_result, staging_result} do
        {:ok, :ok} -> "Both Production and Staging Oban instances healthy"
        _ -> "Prod: #{inspect(prod_result)}, Staging: #{inspect(staging_result)}"
      end

    %{healthy: healthy, message: message}
  end

  @dialyzer {:nowarn_function, safe_check_queue: 2}
  defp safe_check_queue(oban_name, queue) do
    try do
      case Oban.check_queue(name: oban_name, queue: queue) do
        %{} -> :ok
        other -> {:error, other}
      end
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp database_ready? do
    try do
      # Check if at least the Production database is ready
      case Ecto.Adapters.SQL.query(TradeMachine.Repo.Production, "SELECT 1", [], timeout: 1000) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    rescue
      _ -> false
    end
  end
end
