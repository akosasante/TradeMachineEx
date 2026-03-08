defmodule TradeMachine.MinorLeagues.SheetFetcher do
  @moduledoc """
  Fetches minor league roster data from a public Google Sheet as CSV.

  Uses the Google Sheets CSV export endpoint, which requires no authentication
  for public sheets. Req auto-decodes the CSV into a list of lists when
  `nimble_csv` is available as a dependency.
  """

  require Logger

  @base_url "https://docs.google.com/spreadsheets/d"

  @doc """
  Fetches the minor league sheet as CSV and returns the auto-decoded rows.

  ## Parameters
    - `sheet_id` - Google Sheets spreadsheet ID
    - `gid` - Tab/sheet GID within the spreadsheet

  ## Returns
    - `{:ok, rows}` where `rows` is a list of lists (auto-decoded by Req + NimbleCSV)
    - `{:error, reason}` on failure
  """
  @spec fetch(String.t(), String.t()) :: {:ok, [[String.t()]]} | {:error, term()}
  def fetch(sheet_id, gid) do
    url = "#{@base_url}/#{sheet_id}/export?format=csv&gid=#{gid}"

    Logger.info("Fetching minor league sheet", sheet_id: sheet_id, gid: gid)

    req =
      Req.new(url: url, redirect_log_level: false)
      |> Req.merge(Application.get_env(:trade_machine, :sheet_fetcher_req_options, []))

    case Req.get(req) do
      {:ok, %{status: 200, body: rows}} when is_list(rows) ->
        Logger.info("Fetched minor league sheet", row_count: length(rows))
        {:ok, rows}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Logger.warning("CSV auto-decoding did not trigger; got binary body",
          body_preview: String.slice(body, 0..200)
        )

        {:error, :unexpected_binary_body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch minor league sheet",
          status: status,
          body_preview: if(is_binary(body), do: String.slice(body, 0..200), else: inspect(body))
        )

        {:error, {:http_status, status}}

      {:error, reason} ->
        Logger.error("HTTP request failed for minor league sheet", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Convenience function that reads sheet_id and gid from application config.
  """
  @spec fetch_from_config() :: {:ok, [[String.t()]]} | {:error, term()}
  def fetch_from_config do
    sheet_id = Application.fetch_env!(:trade_machine, :minor_league_sheet_id)
    gid = Application.get_env(:trade_machine, :minor_league_sheet_gid, "806978055")
    fetch(sheet_id, gid)
  end
end
