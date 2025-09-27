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
      database: database_check()
      #      google_sheets: sheets_check(),
      #      oban: oban_check()
    }

    healthy = Enum.all?(checks, fn {_service, status} -> status.healthy end)

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
      # Simple database connectivity test
      case Ecto.Adapters.SQL.query(TradeMachine.Repo, "SELECT 1", [], timeout: 5000) do
        {:ok, _} ->
          %{healthy: true, message: "Database connection successful"}

        {:error, error} ->
          %{healthy: false, message: "Database error: #{inspect(error)}"}
      end
    rescue
      error ->
        %{healthy: false, message: "Database exception: #{inspect(error)}"}
    end
  end

  #  defp sheets_check do
  #    try do
  #      # Check if Google Sheets processes are running
  #      goth_alive = Process.whereis(TradeMachine.Goth) != nil
  #      reader_alive = Process.whereis(TradeMachine.SheetReader) != nil
  #
  #      case {goth_alive, reader_alive} do
  #        {true, true} ->
  #          %{healthy: true, message: "Google Sheets integration healthy"}
  #        {false, true} ->
  #          %{healthy: false, message: "Goth (Google Auth) process not running"}
  #        {true, false} ->
  #          %{healthy: false, message: "SheetReader process not running"}
  #        {false, false} ->
  #          %{healthy: false, message: "Both Goth and SheetReader processes not running"}
  #      end
  #    rescue
  #      error ->
  #        %{healthy: false, message: "Sheets check exception: #{inspect(error)}"}
  #    end
  #  end

  #  defp oban_check do
  #    try do
  #      # Check if Oban is running and queues are operational
  #      case Oban.check_queue(TradeMachine.Repo, queue: "minors_sync") do
  #        {:ok, _stats} ->
  #          %{healthy: true, message: "Oban job processing healthy"}
  #        {:error, error} ->
  #          %{healthy: false, message: "Oban error: #{inspect(error)}"}
  #      end
  #    rescue
  #      error ->
  #        %{healthy: false, message: "Oban check exception: #{inspect(error)}"}
  #    end
  #  end

  defp database_ready? do
    try do
      case Ecto.Adapters.SQL.query(TradeMachine.Repo, "SELECT 1", [], timeout: 1000) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    rescue
      _ -> false
    end
  end

  #  defp dependencies_ready? do
  #    # Check critical dependencies are running
  #    Process.whereis(TradeMachine.Goth) != nil &&
  #    Process.whereis(TradeMachine.SheetReader) != nil
  #  end
end
