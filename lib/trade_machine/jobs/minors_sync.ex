defmodule TradeMachine.Jobs.MinorsSync do
  @moduledoc """
  Oban worker for syncing minor league player data from Google Sheets.

  This job runs daily at 2:00 AM UTC via cron schedule.
  It reads the minor league spreadsheet and updates player records.
  """

  alias TradeMachine.SheetReader
  alias TradeMachine.SyncTracking

  use Oban.Worker, queue: :minors_sync, unique: [period: :infinity], max_attempts: 5

  require Logger

  @copy_of_copy_sheet_id "16SjDZBO2vY6rGj9CM7nW2pG21i4pZ85LGlbMCODVQtk"

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    {:ok, execution} =
      SyncTracking.start_sync(:minors_sync, :production,
        oban_job_id: job_id,
        metadata: %{"sheet_id" => @copy_of_copy_sheet_id}
      )

    do_sync_with_tracking(execution)
  end

  defp do_sync_with_tracking(execution) do
    case do_sync() do
      :ok ->
        SyncTracking.complete_sync(execution)
        :ok

      {:ok, metrics} when is_map(metrics) ->
        SyncTracking.complete_sync(execution, metrics)
        :ok

      {:error, reason} = error ->
        SyncTracking.fail_sync(execution, inspect(reason))
        error
    end
  rescue
    e ->
      SyncTracking.fail_sync(execution, Exception.message(e))
      reraise e, __STACKTRACE__
  end

  defp do_sync do
    {:ok, conn} = SheetReader.initialize()
    {:ok, spreadsheet} = SheetReader.get_spreadsheet(conn, @copy_of_copy_sheet_id)

    result = SheetReader.process_minor_league_sheet(conn, spreadsheet)
    Logger.debug(inspect(result, pretty: true))

    :ok
  end
end
