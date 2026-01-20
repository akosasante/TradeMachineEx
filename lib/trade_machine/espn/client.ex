defmodule TradeMachine.ESPN.Client do
  @moduledoc """
  HTTP client for ESPN Fantasy API using Req.

  This module provides functions to interact with the ESPN Fantasy Baseball API,
  including fetching league data, team information, player data, and schedules.

  ## Usage

      # Initialize client with season year
      client = TradeMachine.ESPN.Client.new(2025)

      # Fetch league teams
      {:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client)

      # Fetch all players with pagination
      {:ok, players} = TradeMachine.ESPN.Client.get_all_players(client)

  ## Configuration

  The client requires the following environment variables to be set:
  - ESPN_COOKIE - The espn_s2 cookie value
  - ESPN_SWID - The SWID cookie value
  - ESPN_LEAGUE_ID - The league ID (defaults to "545")
  """

  require Logger

  @base_url_2024_plus "https://lm-api-reads.fantasy.espn.com/apis/v3/games/flb/seasons"
  @base_url_pre_2024 "https://fantasy.espn.com/apis/v3/games/flb/seasons"

  @type t :: %__MODULE__{
          req: Req.Request.t(),
          year: integer(),
          league_id: String.t()
        }

  defstruct [:req, :year, :league_id]

  @doc """
  Creates a new ESPN API client for the specified year.

  ## Parameters
    - year: The season year (e.g., 2025)
    - opts: Optional keyword list with:
      - :espn_cookie - Override ESPN cookie (defaults to config)
      - :swid - Override SWID (defaults to config)
      - :league_id - Override league ID (defaults to config)

  ## Examples

      iex> client = TradeMachine.ESPN.Client.new(2025)
      %TradeMachine.ESPN.Client{year: 2025, ...}

      iex> client = TradeMachine.ESPN.Client.new(2025, league_id: "123")
      %TradeMachine.ESPN.Client{year: 2025, league_id: "123", ...}
  """
  @spec new(integer(), keyword()) :: t()
  def new(year, opts \\ []) do
    espn_cookie = opts[:espn_cookie] || Application.get_env(:trade_machine, :espn_cookie)
    swid = opts[:swid] || Application.get_env(:trade_machine, :espn_swid)
    league_id = opts[:league_id] || Application.get_env(:trade_machine, :espn_league_id) || "545"

    base_url = get_base_url(year, league_id)

    req =
      Req.new(
        base_url: base_url,
        headers: [{"cookie", "espn_s2=#{espn_cookie}; SWID=#{swid};"}],
        receive_timeout: 30_000
      )

    %__MODULE__{
      req: req,
      year: year,
      league_id: league_id
    }
  end

  @doc """
  Fetches all fantasy teams for the league.

  ## Parameters
    - client: The ESPN client struct
    - opts: Optional keyword list with:
      - :view - API view parameter (defaults to "mTeam")
      - :raw - If true, returns raw maps instead of structs (default: false)

  ## Examples

      iex> {:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client)
      {:ok, [%TradeMachine.ESPN.Types.FantasyTeam{id: 1, name: "Team 1", ...}, ...]}

      iex> {:ok, teams} = TradeMachine.ESPN.Client.get_league_teams(client, raw: true)
      {:ok, [%{"id" => 1, "name" => "Team 1", ...}, ...]}
  """
  @spec get_league_teams(t(), keyword()) ::
          {:ok, list(TradeMachine.ESPN.Types.FantasyTeam.t())} | {:error, term()}
  def get_league_teams(client = %__MODULE__{}, opts \\ []) do
    view = opts[:view] || "mTeam"
    raw = opts[:raw] || false

    case Req.get(client.req, url: "/teams", params: [view: view]) do
      {:ok, %{status: 200, body: teams}} ->
        result =
          if raw,
            do: teams,
            else: Enum.map(teams, &TradeMachine.ESPN.Types.FantasyTeam.from_api/1)

        {:ok, result}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ESPN API error fetching teams: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} = error ->
        Logger.error("ESPN API request failed for teams: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetches all league members.

  ## Parameters
    - client: The ESPN client struct
    - opts: Optional keyword list with:
      - :view - API view parameter (defaults to "mNav" for full details)
      - :raw - If true, returns raw maps instead of structs (default: false)

  ## Examples

      iex> {:ok, members} = TradeMachine.ESPN.Client.get_league_members(client)
      {:ok, [%TradeMachine.ESPN.Types.LeagueMember{id: "...", display_name: "User1", ...}, ...]}

      iex> {:ok, members} = TradeMachine.ESPN.Client.get_league_members(client, raw: true)
      {:ok, [%{"id" => "...", "displayName" => "User1", ...}, ...]}
  """
  @spec get_league_members(t(), keyword()) ::
          {:ok, list(TradeMachine.ESPN.Types.LeagueMember.t())} | {:error, term()}
  def get_league_members(client = %__MODULE__{}, opts \\ []) do
    view = opts[:view] || "mNav"
    raw = opts[:raw] || false

    case Req.get(client.req, url: "/members", params: [view: view]) do
      {:ok, %{status: 200, body: members}} ->
        result =
          if raw,
            do: members,
            else: Enum.map(members, &TradeMachine.ESPN.Types.LeagueMember.from_api/1)

        {:ok, result}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ESPN API error fetching members: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} = error ->
        Logger.error("ESPN API request failed for members: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetches the matchup schedule for the season.

  ## Parameters
    - client: The ESPN client struct
    - opts: Optional keyword list with:
      - :view - API view parameter (defaults to "mScoreboard")
      - :raw - If true, returns raw maps instead of structs (default: false)

  ## Examples

      iex> {:ok, schedule} = TradeMachine.ESPN.Client.get_schedule(client)
      {:ok, [%TradeMachine.ESPN.Types.ScheduleMatchup{id: 1, home: %{...}, away: %{...}}, ...]}
  """
  @spec get_schedule(t(), keyword()) ::
          {:ok, list(TradeMachine.ESPN.Types.ScheduleMatchup.t())} | {:error, term()}
  def get_schedule(client = %__MODULE__{}, opts \\ []) do
    view = opts[:view] || "mScoreboard"
    raw = opts[:raw] || false

    case Req.get(client.req, url: "/schedule", params: [view: view]) do
      {:ok, %{status: 200, body: schedule}} ->
        result =
          if raw,
            do: schedule,
            else: Enum.map(schedule, &TradeMachine.ESPN.Types.ScheduleMatchup.from_api/1)

        {:ok, result}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ESPN API error fetching schedule: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} = error ->
        Logger.error("ESPN API request failed for schedule: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetches the roster for a specific team and scoring period.

  ## Parameters
    - client: The ESPN client struct
    - team_id: The team ID
    - scoring_period_id: The scoring period ID
    - opts: Optional keyword list with:
      - :view - API view parameter (defaults to "mRoster")
      - :raw - If true, returns raw map instead of struct (default: false)

  ## Examples

      iex> {:ok, roster} = TradeMachine.ESPN.Client.get_roster(client, 1, 196)
      {:ok, %TradeMachine.ESPN.Types.Roster{entries: [...]}}
  """
  @spec get_roster(t(), integer(), integer(), keyword()) ::
          {:ok, TradeMachine.ESPN.Types.Roster.t()} | {:error, term()}
  def get_roster(client = %__MODULE__{}, team_id, scoring_period_id, opts \\ []) do
    view = opts[:view] || "mRoster"
    raw = opts[:raw] || false

    params = [
      forTeamId: team_id,
      scoringPeriodId: scoring_period_id,
      view: view
    ]

    case Req.get(client.req, url: "", params: params) do
      {:ok, %{status: 200, body: %{"teams" => [team | _]}}} ->
        roster_data = team["roster"]

        result =
          if raw, do: roster_data, else: TradeMachine.ESPN.Types.Roster.from_api(roster_data)

        {:ok, result}

      {:ok, %{status: 200, body: body}} ->
        Logger.error("ESPN API unexpected response format for roster: #{inspect(body)}")
        {:error, {:unexpected_format, body}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ESPN API error fetching roster: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} = error ->
        Logger.error("ESPN API request failed for roster: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetches all MLB players with pagination.

  This function automatically handles pagination, fetching 100 players at a time
  and sleeping 5 seconds between requests to avoid rate limiting.

  ## Parameters
    - client: The ESPN client struct
    - opts: Optional keyword list with:
      - :limit - Number of players per page (default: 100)
      - :sleep_ms - Milliseconds to sleep between requests (default: 5000)
      - :raw - If true, returns raw maps instead of structs (default: false)

  ## Examples

      iex> {:ok, players} = TradeMachine.ESPN.Client.get_all_players(client)
      {:ok, [%TradeMachine.ESPN.Types.PlayerPoolEntry{id: 12345, player: %{...}}, ...]}
  """
  @spec get_all_players(t(), keyword()) ::
          {:ok, list(TradeMachine.ESPN.Types.PlayerPoolEntry.t())} | {:error, term()}
  def get_all_players(client = %__MODULE__{}, opts \\ []) do
    limit = opts[:limit] || 100
    sleep_ms = opts[:sleep_ms] || 5000
    raw = opts[:raw] || false

    case fetch_players_paginated(client, [], 0, limit, sleep_ms, nil) do
      {:ok, players} ->
        result =
          if raw,
            do: players,
            else: Enum.map(players, &TradeMachine.ESPN.Types.PlayerPoolEntry.from_api/1)

        {:ok, result}

      error ->
        error
    end
  end

  # Private helper for paginated player fetching
  defp fetch_players_paginated(client, acc_players, offset, limit, sleep_ms, server_total) do
    filter = %{
      players: %{
        limit: limit,
        offset: offset,
        sortPercOwned: %{
          sortAsc: false,
          sortPriority: 1
        }
      }
    }

    filter_json = Jason.encode!(filter)

    headers = [{"X-Fantasy-Filter", filter_json}]

    case Req.get(client.req, url: "", params: [view: "kona_player_info"], headers: headers) do
      {:ok, %{status: 200, body: %{"players" => players}, headers: resp_headers}} ->
        new_acc = acc_players ++ players
        new_total = length(new_acc)

        # Get server total from headers on first request
        server_total =
          server_total ||
            case resp_headers["x-fantasy-filter-player-count"] do
              [count_str] when is_binary(count_str) -> String.to_integer(count_str)
              _ -> 0
            end

        Logger.debug(
          "Fetched #{length(players)} players (total: #{new_total}/#{server_total || "unknown"})"
        )

        # Check if we need to fetch more
        if server_total > 0 and new_total < server_total do
          # Sleep before next request
          Process.sleep(sleep_ms)
          fetch_players_paginated(client, new_acc, offset + limit, limit, sleep_ms, server_total)
        else
          {:ok, new_acc}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("ESPN API error fetching players: status=#{status}, body=#{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} = error ->
        Logger.error("ESPN API request failed for players: #{inspect(reason)}")
        error
    end
  end

  # Private helper to construct base URL based on year
  defp get_base_url(year, league_id) when year >= 2024 do
    "#{@base_url_2024_plus}/#{year}/segments/0/leagues/#{league_id}"
  end

  defp get_base_url(year, league_id) when year >= 2017 do
    "#{@base_url_pre_2024}/#{year}/segments/0/leagues/#{league_id}"
  end

  defp get_base_url(year, league_id) do
    # For years before 2017, use league history endpoint
    "https://fantasy.espn.com/apis/v3/games/flb/leagueHistory/#{league_id}?seasonId=#{year}"
  end
end
