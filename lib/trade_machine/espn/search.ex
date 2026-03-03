defmodule TradeMachine.ESPN.Search do
  @moduledoc """
  HTTP client for ESPN's public search API.

  Used to discover ESPN player IDs for minor league players who
  aren't in the ESPN Fantasy player pool. Unlike the Fantasy API
  (`TradeMachine.ESPN.Client`), this uses ESPN's public search
  endpoint which covers all players including minor leaguers.

  ## Usage

      {:ok, results} = TradeMachine.ESPN.Search.search_mlb_player("Pedro Pineda")
      # => {:ok, [%{espn_id: 4918086, name: "Pedro Pineda", team: "...", ...}]}
  """

  require Logger

  @search_url "https://site.web.api.espn.com/apis/search/v2"

  @type search_result :: %{
          espn_id: integer() | nil,
          name: String.t(),
          team: String.t() | nil,
          description: String.t() | nil,
          league_slug: String.t() | nil,
          uid: String.t() | nil,
          image_url: String.t() | nil
        }

  @doc """
  Search for MLB players by name using ESPN's public search API.

  Returns `{:ok, results}` where results is a list of MLB baseball player
  matches with extracted ESPN IDs, or `{:error, reason}`.

  Only returns results where `sport == "baseball"`.

  ## Options
    - `:limit` - max results per search (default: 10)
  """
  @spec search_mlb_player(String.t(), keyword()) :: {:ok, [search_result()]} | {:error, term()}
  def search_mlb_player(name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    params = [
      region: "us",
      lang: "en",
      section: "mlb",
      limit: limit,
      page: 1,
      platform: "web",
      query: name,
      type: "player"
    ]

    req = build_req()

    case Req.get(req, params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, extract_mlb_players(body)}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("ESPN search API error: status=#{status}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_req do
    Req.new(
      base_url: @search_url,
      headers: [
        {"accept", "application/json"},
        {"origin", "https://www.espn.com"},
        {"referer", "https://www.espn.com/"}
      ],
      receive_timeout: 15_000
    )
  end

  @spec extract_mlb_players(map()) :: [search_result()]
  defp extract_mlb_players(body) when is_map(body) do
    results = body["results"] || []
    player_section = Enum.find(results, fn r -> r["type"] == "player" end)
    contents = (player_section && player_section["contents"]) || []

    contents
    |> Enum.filter(fn c -> c["sport"] == "baseball" end)
    |> Enum.map(fn c ->
      %{
        espn_id: extract_espn_id_from_uid(c["uid"]),
        name: c["displayName"],
        team: c["subtitle"],
        description: c["description"],
        league_slug: c["defaultLeagueSlug"],
        uid: c["uid"],
        image_url: get_in(c, ["image", "default"])
      }
    end)
  end

  defp extract_mlb_players(_), do: []

  @spec extract_espn_id_from_uid(String.t() | nil) :: integer() | nil
  defp extract_espn_id_from_uid(uid) when is_binary(uid) do
    case Regex.run(~r/a:(\d+)/, uid) do
      [_, id_str] -> String.to_integer(id_str)
      _ -> nil
    end
  end

  defp extract_espn_id_from_uid(_), do: nil
end
