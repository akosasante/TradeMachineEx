defmodule TradeMachine.SheetReader do
  alias TradeMachine.SheetReader.State
  require Ecto.Query
  require Logger
  use GenServer

  defmodule State do
    defstruct [:oauth_connection, :spreadsheet]
  end

  defdelegate process_minor_league_sheet(), to: TradeMachine.SheetReader.MinorLeagueReader

  # Client
  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(spreadsheet_id) do
    GenServer.start_link(__MODULE__, spreadsheet_id, name: __MODULE__)
  end

  @spec get_conn() :: Tesla.Client.t()
  def get_conn do
    GenServer.call(__MODULE__, :get_conn)
  end

  @spec get_spreadsheet() :: GoogleApi.Sheets.V4.Model.Spreadsheet.t()
  def get_spreadsheet do
    GenServer.call(__MODULE__, :get_spreadsheet)
  end

  @spec get_spreadsheet_id() :: String.t()
  def get_spreadsheet_id do
    GenServer.call(__MODULE__, :get_spreadsheet_id)
  end

  # GenServer callbacks
  @impl true
  def init(spreadsheet_id) do
    {:ok, token} = Goth.fetch(TradeMachine.Goth)
    conn = GoogleApi.Sheets.V4.Connection.new(token.token)
    {:ok, %State{oauth_connection: conn, spreadsheet: get_spreadsheet(conn, spreadsheet_id)}}
  end

  @impl true
  def handle_call(:get_conn, _from, state = %State{oauth_connection: conn}),
    do: {:reply, conn, state}

  @impl true
  def handle_call(:get_spreadsheet, _from, state = %State{spreadsheet: spreadsheet}),
    do: {:reply, spreadsheet, state}

  @impl true
  def handle_call(:get_spreadsheet_id, _from, state = %State{spreadsheet: spreadsheet}),
    do: {:reply, spreadsheet.spreadsheetId, state}

  ## Private

  defp get_spreadsheet(conn, spreadsheet_id) do
    {:ok, spreadsheet} =
      GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_get(conn, spreadsheet_id)

    spreadsheet
  end

  #  defp get_draft_pick_params_from_sheets(repo, picks_by_owner, season) do
  #    Enum.flat_map(
  #      picks_by_owner,
  #      fn {current_owner, picks} ->
  #        Enum.map(
  #          picks,
  #          fn pick ->
  #            [level, round, original_owner_csv_name] =
  #              case Regex.run(
  #                     ~r/(HM|LM)?\s*(\d+) (\w+)/,
  #                     pick,
  #                     capture: :all_but_first
  #                   ) do
  #                ["HM", round, owner] -> [:high, Decimal.new(round), owner]
  #                ["LM", round, owner] -> [:low, Decimal.new(round), owner]
  #                ["", round, owner] -> [:majors, Decimal.new(round), owner]
  #              end
  #
  #            original_owner =
  #              User
  #              |> Ecto.Query.limit(1)
  #              |> repo.get_by!(csv_name: original_owner_csv_name)
  #
  #            owned_by =
  #              User
  #              |> Ecto.Query.limit(1)
  #              |> repo.get_by!(csv_name: current_owner)
  #
  #            %{
  #              season: season,
  #              type: level,
  #              round: round,
  #              owned_by: owned_by.teamId,
  #              original_owner: original_owner.teamId
  #            }
  #          end
  #        )
  #      end
  #    )
  #  end
end
