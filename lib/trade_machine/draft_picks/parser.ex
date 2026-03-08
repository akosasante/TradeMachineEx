defmodule TradeMachine.DraftPicks.Parser do
  @moduledoc """
  Parses draft picks CSV rows (from Google Sheets) into structured maps.

  ## Sheet structure

  The sheet has 4 groups of 5 owners each (20 owners total). Each owner
  occupies 7 columns in the row:

      [0] Round (decimal)
      [1] Original Owner (csv_name)
      [2] (ignored)
      [3] OVR / pick number (integer)
      [4] Current Owner (csv_name — the owner who currently holds this pick)
      [5] (ignored)
      [6] (ignored)

  Within each group there are 17 pick rows: 10 major league (rows 0–9),
  2 high-minor (rows 10–11), and 5 low-minor (rows 12–16).

  ## State machine

  Parsing uses a state machine to handle the varying structure between
  group 1 (which has a "Round" column-header row) and groups 2–4 (which
  go directly from the owner-name row into pick data rows):

      :scanning   — looking for an owner header row
      :saw_owners — captured owner names; waiting for the "Round" header
                    OR the first pick row (groups 2–4)
      :in_picks   — reading pick rows (index 0..16), then back to :scanning

  ## Cleared picks

  A pick is "cleared" when the sheet Round cell is blank or the OVR value
  is ≤ 0 (e.g. after a draft completes). Cleared picks are excluded from
  the output — they remain in the DB with their last-known state.
  """

  @columns_per_owner 7
  @owners_per_group 5
  @total_columns @columns_per_owner * @owners_per_group
  @picks_per_group 17

  @type parsed_pick :: %{
          type: :majors | :high | :low,
          round: Decimal.t(),
          original_owner_csv: String.t(),
          current_owner_csv: String.t(),
          pick_number: integer()
        }

  @doc """
  Parses a list of CSV rows (list of lists) into draft pick maps.

  Only non-cleared picks are returned. A pick is cleared when its Round
  cell does not parse as a positive decimal or its OVR value is ≤ 0.

  Returns a list of `t:parsed_pick/0` maps.
  """
  @spec parse([[String.t()]]) :: [parsed_pick()]
  def parse(rows) when is_list(rows) do
    rows
    |> Enum.reduce(
      %{state: :scanning, current_owners: [], pick_row_index: 0, picks: []},
      &process_row/2
    )
    |> Map.get(:picks)
  end

  # ---------------------------------------------------------------------------
  # State machine row processor
  # ---------------------------------------------------------------------------

  defp process_row(row, acc) do
    padded = pad_row(row, @total_columns)
    chunks = Enum.chunk_every(padded, @columns_per_owner)
    first_cell = padded |> List.first("") |> String.trim()

    case acc.state do
      :scanning ->
        cond do
          skip_row?(first_cell) ->
            acc

          first_cell == "Round" ->
            acc

          true ->
            %{acc | state: :saw_owners, current_owners: extract_owners(chunks), pick_row_index: 0}
        end

      :saw_owners ->
        cond do
          first_cell == "Round" ->
            %{acc | state: :in_picks}

          skip_row?(first_cell) ->
            acc

          true ->
            # Groups 2–4 have no "Round" header row; the first row after the
            # owner header is already a pick row.
            picks = extract_picks(chunks, acc.current_owners, 0)
            new_index = 1
            new_state = if new_index >= @picks_per_group, do: :scanning, else: :in_picks
            %{acc | state: new_state, picks: acc.picks ++ picks, pick_row_index: new_index}
        end

      :in_picks ->
        picks = extract_picks(chunks, acc.current_owners, acc.pick_row_index)
        new_index = acc.pick_row_index + 1
        new_state = if new_index >= @picks_per_group, do: :scanning, else: :in_picks
        %{acc | picks: acc.picks ++ picks, pick_row_index: new_index, state: new_state}
    end
  end

  # ---------------------------------------------------------------------------
  # Row helpers
  # ---------------------------------------------------------------------------

  defp skip_row?(cell) do
    cell == "" or
      cell == "Draft Picks" or
      String.starts_with?(cell, "GREY") or
      String.starts_with?(cell, "BLUE") or
      String.starts_with?(cell, "RED")
  end

  defp extract_owners(chunks) do
    chunks
    |> Enum.take(@owners_per_group)
    |> Enum.map(fn chunk -> chunk |> List.first("") |> String.trim() end)
  end

  defp extract_picks(chunks, current_owners, pick_row_index) do
    type = pick_type(pick_row_index)

    chunks
    |> Enum.take(@owners_per_group)
    |> Enum.with_index()
    |> Enum.flat_map(fn {chunk, owner_idx} ->
      current_owner = Enum.at(current_owners, owner_idx, "")
      round_str = chunk |> Enum.at(0, "") |> String.trim()
      orig_owner = chunk |> Enum.at(1, "") |> String.trim()
      ovr_str = chunk |> Enum.at(3, "") |> String.trim()

      with {round, _} <- Decimal.parse(round_str),
           :gt <- Decimal.compare(round, Decimal.new(0)),
           {ovr, _} <- Integer.parse(ovr_str),
           true <- ovr > 0,
           false <- orig_owner == "" do
        [
          %{
            type: type,
            round: round,
            original_owner_csv: orig_owner,
            current_owner_csv: current_owner,
            pick_number: ovr
          }
        ]
      else
        _ -> []
      end
    end)
  end

  # Row index within the group (0-indexed)
  defp pick_type(i) when i in 0..9, do: :majors
  defp pick_type(i) when i in 10..11, do: :high
  defp pick_type(i) when i in 12..16, do: :low
  defp pick_type(_), do: :unknown

  defp pad_row(row, expected) when length(row) >= expected, do: row
  defp pad_row(row, expected), do: row ++ List.duplicate("", expected - length(row))
end
