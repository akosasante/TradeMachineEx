defmodule TradeMachine.SheetReader do
  alias TradeMachine.Repo
  alias TradeMachine.Data.Player.IncomingMinorLeaguer
  alias TradeMachine.Data.Player
  alias TradeMachine.Data.User
  alias TradeMachine.Data.DraftPick
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

    Logger.debug("Minor league sheet: #{inspect(minor_league_sheet, pretty: true)}")

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

    Logger.debug("Player ranges: #{inspect(player_ranges_by_owner_name, pretty: true)}")

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

    Logger.debug("Finalized list of incoming players: #{inspect(list_of_incoming_players, pretty: true)}")
    Player.batch_insert_minor_leaguers(list_of_incoming_players)
  end

  def process_draft_pick_sheet(conn, spreadsheet_id, sheet_name, season) do
    name_row = 2
    hm_start_row = 14
    lm_start_row = 22

    {:ok, %GoogleApi.Sheets.V4.Model.ValueRange{values: values}} =
      GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_values_get(
        conn,
        spreadsheet_id,
        "'#{sheet_name}'!R#{name_row}C1:R#{name_row}C20"
      )

    names =
      values
      |> List.flatten()

    picks_by_owner =
      names
      |> Enum.with_index(1)
      |> Enum.reduce(
           %{},
           fn {name, column}, map ->
             :timer.sleep(2000)
             {
               :ok,
               %GoogleApi.Sheets.V4.Model.ValueRange{values: high_minors}
             } =
               GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_values_get(
                 conn,
                 spreadsheet_id,
                 "'#{sheet_name}'!R#{hm_start_row}C#{column}:R#{hm_start_row + 6}C#{column}"
               )

             {
               :ok,
               %GoogleApi.Sheets.V4.Model.ValueRange{values: low_minors}
             } =
               GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_values_get(
                 conn,
                 spreadsheet_id,
                 "'#{sheet_name}'!R#{lm_start_row}C#{column}:R#{lm_start_row + 6}C#{column}"
               )

             {
               :ok,
               %GoogleApi.Sheets.V4.Model.ValueRange{values: majors}
             } =
               GoogleApi.Sheets.V4.Api.Spreadsheets.sheets_spreadsheets_values_get(
                 conn,
                 spreadsheet_id,
                 "'#{sheet_name}'!R#{name_row + 1}C#{column}:R#{name_row + 10}C#{column}"
               )

             Map.put(
               map,
               name,
               Enum.concat(
                 [
                   high_minors
                   |> List.flatten()
                   |> Enum.reject(&(&1 == "#N/A")),
                   low_minors
                   |> List.flatten()
                   |> Enum.reject(&(&1 == "#N/A")),
                   majors
                   |> List.flatten()
                   |> Enum.reject(&(&1 == "#N/A"))
                 ]
               )
             )
           end
         )

    Ecto.Multi.new()
    |> Ecto.Multi.run(
         :generate_params,
         fn repo, _changes ->
           {:ok, get_draft_pick_params_from_sheets(repo, picks_by_owner, season)}
         end
       )
    |> Ecto.Multi.run(
         :fetch_existing,
         fn repo, _changes ->
           {
             :ok,
             DraftPick
             |> Ecto.Query.preload([:owned_by, :original_owner])
             |> repo.all()
           }
         end
       )
    |> Ecto.Multi.run(
         :drop_existing_entries,
         fn _repo, %{generate_params: incoming_params, fetch_existing: existing_picks} ->
           incoming_picks_mapset = MapSet.new(incoming_params)

           existing_picks_mapset =
             MapSet.new(
               existing_picks,
               fn pick ->
                 %{
                   season: pick.season,
                   type: pick.type,
                   round: pick.round,
                   owned_by: pick.currentOwnerId,
                   original_owner: pick.originalOwnerId
                 }
               end
             )

           picks_to_upsert = MapSet.difference(incoming_picks_mapset, existing_picks_mapset)

           picks_to_unset =
             MapSet.difference(existing_picks_mapset, incoming_picks_mapset)
             |> then(
                  fn unset_mapset ->
                    Enum.filter(
                      existing_picks,
                      &Enum.member?(
                        unset_mapset,
                        %{
                          season: &1.season,
                          type: &1.type,
                          round: &1.round,
                          owned_by: &1.currentOwnerId,
                          original_owner: &1.originalOwnerId
                        }
                      )
                    )
                  end
                )


           {:ok, [picks_to_upsert: picks_to_upsert, picks_to_unset: picks_to_unset]}
         end
       )
    |> Ecto.Multi.run(
         :build_upsert_list,
         fn _repo,
            %{
              fetch_existing: existing_picks,
              drop_existing_entries: [
                picks_to_upsert: picks_to_upsert,
                picks_to_unset: picks_to_unset
              ]
            } ->
           {changesets, picks_to_clear} =
             Enum.reduce(
               picks_to_upsert,
               {[], picks_to_unset},
               fn pick, acc ->
                 {cs, updated_picks_to_clear} =
                   case Enum.find(
                          existing_picks,
                          fn existing_pick ->
                            existing_pick.season == pick.season and existing_pick.type == pick.type and
                            existing_pick.round == pick.round and
                            existing_pick.originalOwnerId == pick.original_owner
                          end
                        ) do
                     %DraftPick{} = matching_pick ->
                       IO.puts(
                         "Found a matching existing pick: #{inspect(pick)} vs #{
                           inspect(matching_pick)
                         }. Just gonna update the current owner team id"
                       )

                       cs =
                         DraftPick.changeset(
                           matching_pick,
                           pick
                           |> Map.put(:currentOwnerId, pick.owned_by)
                           |> Map.put(:originalOwnerId, pick.original_owner)
                         )

                       {cs, Enum.reject(elem(acc, 1), &(&1 == matching_pick))}

                     nil ->
                       IO.puts("Did not find a matching pick for #{inspect(pick)}")

                       cs =
                         DraftPick.new(
                           pick
                           |> Map.put(:currentOwnerId, pick.owned_by)
                           |> Map.put(:originalOwnerId, pick.original_owner)
                         )

                       {cs, elem(acc, 1)}
                   end

                 {[cs | elem(acc, 0)], updated_picks_to_clear}
               end
             )

           {:ok, [changesets_to_upsert: changesets, picks_to_clear: picks_to_clear]}
         end
       )
    |> Ecto.Multi.run(
         :upsert,
         fn repo,
            %{
              build_upsert_list: [
                changesets_to_upsert: changesets_to_upsert,
                picks_to_clear: _
              ]
            } ->
           results = Enum.map(changesets_to_upsert, fn cs -> repo.insert_or_update(cs) end)
           {:ok, results}
         end
       )
    |> Ecto.Multi.update_all(
         :unset_existing_pick_owners,
         fn %{
              build_upsert_list: [
                changesets_to_upsert: _,
                picks_to_clear: picks_to_clear
              ]
            } ->
           ids = Enum.map(picks_to_clear, & &1.id)

           DraftPick
           |> Ecto.Query.where([p], p.id in ^ids)
         end,
         set: [
           currentOwnerId: nil
         ]
       )
    |> Repo.transaction()
  end

  defp get_draft_pick_params_from_sheets(repo, picks_by_owner, season) do
    Enum.flat_map(
      picks_by_owner,
      fn {current_owner, picks} ->
        Enum.map(
          picks,
          fn pick ->
            [level, round, original_owner_csv_name] =
              case Regex.run(
                     ~r/(HM|LM)?\s*(\d+) (\w+)/,
                     pick,
                     capture: :all_but_first
                   ) do
                ["HM", round, owner] -> [:high, Decimal.new(round), owner]
                ["LM", round, owner] -> [:low, Decimal.new(round), owner]
                ["", round, owner] -> [:majors, Decimal.new(round), owner]
              end

            original_owner =
              User
              |> Ecto.Query.limit(1)
              |> repo.get_by!(csv_name: original_owner_csv_name)

            owned_by =
              User
              |> Ecto.Query.limit(1)
              |> repo.get_by!(csv_name: current_owner)

            %{
              season: season,
              type: level,
              round: round,
              owned_by: owned_by.teamId,
              original_owner: original_owner.teamId
            }
          end
        )
      end
    )
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

    IO.inspect(team_id, label: :team_id)

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
    ) |> IO.inspect(label: :concatted)
  end
end
