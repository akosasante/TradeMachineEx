defmodule TradeMachine.SheetReader do
  alias TradeMachine.Repo
  alias TradeMachine.Data.Player.IncomingMinorLeaguer
  alias TradeMachine.Data.Player
  alias TradeMachine.Data.User
  require Ecto.Query
  require Logger

  def initialize() do
    {:ok, token} = Goth.fetch(TradeMachine.Goth)
    conn = GoogleApi.Sheets.V4.Connection.new(token.token)
    {:ok, conn}
  end

  def get_spreadsheet(conn, spreadsheet_id) do
    {:ok, _spreadsheet} =
      GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_get(conn, spreadsheet_id)
  end

  def process_minor_league_sheet(conn, spreadsheet) do
    minor_league_sheet =
      spreadsheet.sheets
      |> Enum.find(&(Map.get(&1.properties, :title) == "Minor League Rosters"))

    # Merged cells indicate places where we have team owner names or the high/low minors labels
    merged_cells = minor_league_sheet.merges

    last_row =
      Enum.sort_by(merged_cells, & &1.startRowIndex)
      |> Enum.at(-1)

    # Sort them in order of row (so like reading the sheet top to bottom), remove the title and footer rows of the table, then group each set of things that sit on the same column
    # End with a map like %{ <column_number>: [<list_of_merge_objects_at_that_column_ordered_by_row>] }
    merged_cells_grouped_by_column_after_filter =
      Enum.sort_by(merged_cells, & &1.startRowIndex)
      |> Enum.slice(1..-2)
      |> Enum.group_by(& &1.startColumnIndex)

    # Now label each of those columns with whether it represents a name, high minors, or low minors. We know those are the only options and always repeat in that order.
    # End with a map like %{ <column_number>: [ <label>: [<list_of_merge_objects_at_that_column_ordered_by_row>] ] }
    merged_cells_by_col_with_type =
      merged_cells_grouped_by_column_after_filter
      |> Enum.map(fn {column, list_of_merges_in_column} ->
        appended =
          Stream.cycle([:name, :high, :low])
          |> Stream.zip(list_of_merges_in_column)
          |> Enum.to_list()

        {column, appended}
      end)
      |> Map.new()

    # Convert the map of list of merges, to a list of tuples where the first value is the name of the owner, and the second value is a mpa, in the form:
    # [ { <owner_name>, %{ high: "R#{start_row}C#{start_col}:R#{end_row}C#{end_col}", low: "R#{start_row}C#{start_col}:R#{end_row}C#{end_col}" } } ]
    player_ranges_by_owner_name =
      merged_cells_by_col_with_type
      |> Enum.flat_map(fn {_column, list_of_appended_merges} ->
        group_player_ranges_by_owner_name(
          conn,
          spreadsheet.spreadsheetId,
          last_row,
          list_of_appended_merges
        )
      end)

    get_players_by_owner_name =
      player_ranges_by_owner_name
      |> Enum.map(fn [{name, %{high: high_range, low: low_range}}] ->
        {:ok, %GoogleApi.Sheets.V4.Model.ValueRange{values: high_minors_players}} =
          GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_values_get(
            conn,
            spreadsheet.spreadsheetId,
            high_range
          )

        {:ok, %GoogleApi.Sheets.V4.Model.ValueRange{values: low_minors_players}} =
          GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_values_get(
            conn,
            spreadsheet.spreadsheetId,
            low_range
          )

        if name == "Jeremiah" do
          IO.inspect(low_minors_players)
        end

        [
          {
            name,
            %{
              high:
                high_minors_players
                |> Enum.reject(fn
                  ["#N/A", _, _] -> true
                  _ -> false
                end),
              low:
                low_minors_players
                |> Enum.reject(fn
                  ["#N/A", _, _] -> true
                  _ -> false
                end)
            }
          }
        ]
        |> Map.new()
      end)

    list_of_incoming_players =
      Enum.flat_map(
        get_players_by_owner_name,
        &(&1
          |> Map.to_list()
          |> convert_sheet_names_to_incoming_players())
      )

    Player.batch_insert_minor_leaguers(list_of_incoming_players)
  end

  defp group_player_ranges_by_owner_name(
         conn,
         spreadsheet_id,
         last_row,
         merged_cells_grouped_by_col_with_type
       ) do
    merged_cells_grouped_by_col_with_type
    # grab the :name, :high, :low, and the next :name, from the keyword list for a given column
    |> Enum.chunk_every(4, 3)
    |> Enum.map(fn tuple ->
      names = Keyword.get_values(tuple, :name)
      curr_name = hd(names)
      next_name = Enum.at(names, 1)
      high = Keyword.get(tuple, :high)
      low = Keyword.get(tuple, :low)

      # Get the name of the owner at the merged cell labeled :name
      # values is a list of result lists, so we gotta flat_map
      {:ok, %GoogleApi.Sheets.V4.Model.ValueRange{values: values}} =
        GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_values_get(
          conn,
          spreadsheet_id,
          "R#{curr_name.startRowIndex + 1}C#{curr_name.startColumnIndex + 1}"
        )

      name =
        values
        |> Enum.flat_map(& &1)
        |> hd

      # All the high minors players will be listed in the three columns starting from the column indicated by the merged cell labeled :high
      # They will be listed as far as the starting row for the merged cell labeled :low
      range_for_high =
        "R#{high.startRowIndex + 2}C#{high.startColumnIndex + 1}:R#{low.startRowIndex}C#{low.startColumnIndex + 3}"

      # All the low minors players will be listed in the three columns starting from the column indicated by the merged cell labeled :low
      # They will be listed as far as the starting row for the merged cell labeled :name (for the next name down)
      range_for_low =
        "R#{low.startRowIndex + 2}C#{low.startColumnIndex + 1}:R#{if next_name, do: next_name.startRowIndex, else: last_row.startRowIndex}C#{curr_name.startColumnIndex + 3}"

      [{name, %{high: range_for_high, low: range_for_low}}]
    end)
  end

  defp convert_sheet_names_to_incoming_players([
         {owner_csv_name, %{high: high_minors, low: low_minors}}
       ]) do
    user =
      User
      |> Ecto.Query.limit(1)
      |> Repo.get_by(csv_name: owner_csv_name)

    team_id =
      case user do
        %User{teamId: team_id} ->
          team_id

        nil ->
          Logger.error("Could not find user with this CSV name #{owner_csv_name}")
          nil
      end

    Enum.concat(
      Enum.map(
        high_minors,
        fn [player_name, position, mlb_team] ->
          %IncomingMinorLeaguer{
            name: player_name,
            league: :minor,
            owner_id: team_id,
            position: position,
            mlb_team: mlb_team,
            league_level: "High"
          }
        end
      ),
      Enum.map(
        low_minors,
        fn [player_name, position, mlb_team] ->
          %IncomingMinorLeaguer{
            name: player_name,
            league: :minor,
            owner_id: team_id,
            position: position,
            mlb_team: mlb_team,
            league_level: "Low"
          }
        end
      )
    )
  end
end
