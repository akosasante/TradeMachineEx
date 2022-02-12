defmodule TradeMachine.Jobs.MinorsSync do
  alias TradeMachine.SheetReader

  use Oban.Worker, queue: :minors_sync, unique: [period: :infinity], max_attempts: 5

  @copy_of_copy_sheet_id "16SjDZBO2vY6rGj9CM7nW2pG21i4pZ85LGlbMCODVQtk"

  @impl Oban.Worker
  def perform(oban_job) do
    IO.puts("The oban job: #{inspect(oban_job)}")

    {:ok, conn} = SheetReader.initialize()

    {:ok, spreadsheet} = SheetReader.get_spreadsheet(conn, @copy_of_copy_sheet_id)

    SheetReader.process_minor_league_sheet(conn, spreadsheet)
    |> IO.inspect(label: :result)

    :ok
  end
end