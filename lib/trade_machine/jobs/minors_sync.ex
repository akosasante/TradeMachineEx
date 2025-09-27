defmodule TradeMachine.Jobs.MinorsSync do
  alias TradeMachine.SheetReader

  use Oban.Worker, queue: :minors_sync, unique: [period: :infinity], max_attempts: 5

  require Logger

  @copy_of_copy_sheet_id "16SjDZBO2vY6rGj9CM7nW2pG21i4pZ85LGlbMCODVQtk"

  @impl Oban.Worker
  def perform(oban_job) do
    Logger.debug("The oban job: #{inspect(oban_job)}")

    {:ok, conn} = SheetReader.initialize()

    {:ok, spreadsheet} = SheetReader.get_spreadsheet(conn, @copy_of_copy_sheet_id)

    result = SheetReader.process_minor_league_sheet(conn, spreadsheet)
    Logger.debug(inspect(result, pretty: true))

    :ok
  end
end
