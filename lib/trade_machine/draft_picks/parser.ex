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

  Within each group there are 15 pick rows: 10 major league (rows 0–9),
  1 high-minor (row 10), and 4 low-minor (rows 11–14).

  ## State machine

  Parsing uses a state machine to handle the varying structure between
  group 1 (which has a "Round" column-header row) and groups 2–4 (which
  go directly from the owner-name row into pick data rows):

      :scanning   — looking for an owner header row
      :saw_owners — captured owner names; waiting for the "Round" header
                    OR the first pick row (groups 2–4)
      :in_picks   — reading pick rows (index 0..14), then back to :scanning

  ## Cleared picks

  A pick is "cleared" when the sheet Round cell is blank or the OVR value
  is ≤ 0 (e.g. after a draft completes). Cleared picks are excluded from
  the output — they remain in the DB with their last-known state.
  """

  @columns_per_owner 7
  @owners_per_group 5
  @total_columns @columns_per_owner * @owners_per_group
  @picks_per_group 15

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
  cell does not parse as a positive number or its OVR value is ≤ 0.

  HM and LM round labels ("HM1", "LM1", "LM3", "LM4", "LM5") are parsed
  by stripping the non-numeric prefix and converting the remaining digits
  to a `Decimal` (e.g. "HM1" → 1, "LM3" → 3).

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
      :scanning -> handle_scanning(acc, chunks, first_cell)
      :saw_owners -> handle_saw_owners(acc, chunks, first_cell)
      :in_picks -> handle_in_picks(acc, chunks)
    end
  end

  defp handle_scanning(acc, chunks, first_cell) do
    if skip_row?(first_cell) or first_cell == "Round" do
      acc
    else
      %{acc | state: :saw_owners, current_owners: extract_owners(chunks), pick_row_index: 0}
    end
  end

  defp handle_saw_owners(acc, chunks, first_cell) do
    cond do
      first_cell == "Round" ->
        %{acc | state: :in_picks}

      skip_row?(first_cell) ->
        acc

      true ->
        # Groups 2–4 have no "Round" header row; the first row after the
        # owner header is already a pick row.
        advance_picks(acc, chunks, 0)
    end
  end

  defp handle_in_picks(acc, chunks) do
    advance_picks(acc, chunks, acc.pick_row_index)
  end

  defp advance_picks(acc, chunks, pick_row_index) do
    picks = extract_picks(chunks, acc.current_owners, pick_row_index)
    new_index = pick_row_index + 1
    new_state = if new_index >= @picks_per_group, do: :scanning, else: :in_picks
    %{acc | state: new_state, picks: acc.picks ++ picks, pick_row_index: new_index}
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

      with {:ok, round} <- parse_round(round_str),
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

  # Row index within the group (0-indexed):
  # rows 0–9 → 10 major league picks
  # row 10   → 1 high-minor pick (round label "HM1")
  # rows 11–14 → 4 low-minor picks (round labels "LM1", "LM3", "LM4", "LM5")
  defp pick_type(i) when i in 0..9, do: :majors
  defp pick_type(10), do: :high
  defp pick_type(i) when i in 11..14, do: :low
  defp pick_type(_), do: :unknown

  # Parses a round string to a positive Decimal.
  # Handles plain numbers ("1", "2.0") as well as prefixed HM/LM labels
  # ("HM1" → 1, "LM3" → 3) by stripping any non-numeric prefix.
  defp parse_round(str) do
    normalized = String.replace(str, ~r/[^0-9.]/, "")

    case Decimal.parse(normalized) do
      {decimal, ""} -> {:ok, decimal}
      _ -> :error
    end
  end

  defp pad_row(row, expected) when length(row) >= expected, do: row
  defp pad_row(row, expected), do: row ++ List.duplicate("", expected - length(row))
end
