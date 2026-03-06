defmodule TradeMachine.MinorLeagues.Parser do
  @moduledoc """
  Parses minor league roster CSV data from the Google Sheet export.

  The sheet has a repeating structure: 5 teams are arranged horizontally per
  "group" (groups 1-4), each occupying 9 columns. A header row identifies team
  owners, followed by HM (High Minors) and LM (Low Minors) player rows.

  ## Column layout per team chunk (9 columns, 0-indexed):

      [0] group number (1-4)
      [1] level — "0" for header, "HM" for high minors, "LM" for low minors
      [2] position number (1-7) or "#N/A"
      [3] name — owner name in headers, player name in player rows
      [4] annotation (*, **, X, or empty)
      [5] position abbreviation (P, C, 1B, 2B, 3B, SS, OF)
      [6] MLB team abbreviation
      [7] keep flag ("K" in header, "FALSE"/"TRUE" in player rows)
      [8] trade flag ("T" in header, "FALSE"/"TRUE" in player rows)
  """

  require Logger

  @columns_per_team 9
  @teams_per_group 5

  @type parsed_player :: %{
          name: String.t(),
          league_level: String.t(),
          position: String.t(),
          mlb_team: String.t(),
          owner_csv_name: String.t()
        }

  @doc """
  Parses minor league roster data into a flat list of parsed player maps.

  Accepts either:
  - A list of lists (auto-decoded output from Req + NimbleCSV)
  - A raw CSV binary string (decoded via NimbleCSV)
  """
  @spec parse([[String.t()]] | String.t()) :: [parsed_player()]
  def parse(rows) when is_list(rows) do
    do_parse(rows)
  end

  def parse(csv) when is_binary(csv) do
    csv
    |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
    |> do_parse()
  end

  defp do_parse(rows) do
    expected_cols = @columns_per_team * @teams_per_group

    rows
    |> Enum.reduce(%{current_owners: [], players: []}, fn row, acc ->
      padded_row = pad_row(row, expected_cols)
      team_chunks = Enum.chunk_every(padded_row, @columns_per_team)

      case classify_row(team_chunks) do
        :header ->
          %{acc | current_owners: extract_owners(team_chunks)}

        :player ->
          new_players = extract_players(team_chunks, acc.current_owners)
          %{acc | players: acc.players ++ new_players}

        :skip ->
          acc
      end
    end)
    |> Map.get(:players)
  end

  defp extract_owners(team_chunks) do
    team_chunks
    |> Enum.take(@teams_per_group)
    |> Enum.map(fn chunk -> Enum.at(chunk, 3, "") |> String.trim() end)
  end

  defp extract_players(team_chunks, current_owners) do
    team_chunks
    |> Enum.take(@teams_per_group)
    |> Enum.with_index()
    |> Enum.flat_map(fn {chunk, team_idx} ->
      parse_player(chunk, Enum.at(current_owners, team_idx, ""))
    end)
  end

  @doc false
  def classify_row(team_chunks) do
    first_chunk = List.first(team_chunks, [])
    level = Enum.at(first_chunk, 1, "") |> String.trim()
    name = Enum.at(first_chunk, 3, "") |> String.trim()
    group = Enum.at(first_chunk, 0, "") |> String.trim()

    cond do
      level == "0" and name != "" ->
        :header

      level in ["HM", "LM"] and has_any_players?(team_chunks) ->
        :player

      group == "Row" ->
        :skip

      true ->
        :skip
    end
  end

  defp has_any_players?(team_chunks) do
    Enum.any?(team_chunks, fn chunk ->
      name = Enum.at(chunk, 3, "") |> String.trim()
      name != "" and name != "#N/A"
    end)
  end

  defp parse_player(chunk, owner_csv_name) do
    name = Enum.at(chunk, 3, "") |> String.trim()
    level = Enum.at(chunk, 1, "") |> String.trim()
    position = Enum.at(chunk, 5, "") |> String.trim()
    mlb_team = Enum.at(chunk, 6, "") |> String.trim()

    if name != "" and name != "#N/A" and level in ["HM", "LM"] do
      [
        %{
          name: name,
          league_level: level,
          position: position,
          mlb_team: mlb_team,
          owner_csv_name: owner_csv_name
        }
      ]
    else
      []
    end
  end

  defp pad_row(row, expected_cols) when length(row) >= expected_cols, do: row

  defp pad_row(row, expected_cols) do
    row ++ List.duplicate("", expected_cols - length(row))
  end
end
