defmodule TradeMachine.Data.Player do
  defmodule IncomingMinorLeaguer do
    # Not using TradeMachine.Schema because this doesn't have primary key, or other shared fields
    use TypedEctoSchema
    require Logger

    typed_embedded_schema do
      field :name, :string, null: false

      field(
        :league,
        Ecto.Enum,
        values: [
          minor: "2"
        ],
        null: false
      )

      # TODO can this be DRY-ed?
      field(:owner_id, Ecto.UUID, null: false)
      # TODO We can make this Enum probably
      field :position, :string
      field :mlb_team, :string
      field(:league_level, :string, null: false)
    end
  end

  use TradeMachine.Schema

  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Player.IncomingMinorLeaguer
  alias TradeMachine.Data.Team

  require Ecto.Query
  require Logger

  # Used for creating maps for making some of our multis more efficient
  # Currently this is always a concatenated string of these fields: name+league+level+mlb_team+position+owner
  @type search_key() :: String.t()

  @required_fields [:name, :league]
  @optional_fields [:mlb_team, :player_data_id, :meta, :leagueTeamId]

  typed_schema "player" do
    field :name, :string, null: false

    field(
      :league,
      Ecto.Enum,
      values: [
        major: "1",
        minor: "2"
      ],
      null: false
    )

    # TODO: check inclusion at changeset cast
    field :mlb_team, :string
    field :player_data_id, :integer
    field :meta, :map, load_in_query: false

    belongs_to :owned_by, Team, source: :leagueTeamId, foreign_key: :leagueTeamId

    timestamps()
  end

  def new(params \\ %{}) do
    changeset(%__MODULE__{}, params)
  end

  def changeset(struct = %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @spec get_all_minor_leaguers() :: list(__MODULE__.t())
  def get_all_minor_leaguers do
    __MODULE__
    # TODO: maybe import ecto.query so we don't need all this
    |> Ecto.Query.where(
      [p],
      p.league == :minor and not is_nil(p.leagueTeamId) and not is_nil(p.meta)
    )
    # TODO Potentially make this part optional
    |> Ecto.Query.preload(:owned_by)
    # TODO: Potentially make this part optional
    # TODO: What exactly does this do?? oh because that field is not automatically pulled
    |> Ecto.Query.select([p], %Player{p | meta: p.meta})
    # TODO This is just for testing
    #    |> Ecto.Query.limit(5)
    # TODO: maybe alias here
    |> TradeMachine.Repo.all()
  end

  @spec batch_insert_minor_leaguers(list(IncomingMinorLeaguer.t())) ::
          {:ok,
           %{
             fetch_existing: list(__MODULE__.t()),
             calculate_diffs: [
               players_to_insert: MapSet.t(String.t()),
               players_to_clear: MapSet.t(String.t()),
               players_to_update: list(String.t()),
               existing_player_map: %{String.t() => __MODULE__.t()},
               incoming_player_map: %{String.t() => IncomingMinorLeaguer.t()}
             ],
             upsert: list({:ok, __MODULE__.t()} | {:error, Ecto.Changeset.t()}),
             unset_existing_player_teams: {integer(), nil | [term()]}
           }}
  def batch_insert_minor_leaguers(incoming_minor_leaguers) do
    Ecto.Multi.new()
    # (1) fetch current minor leaguers that are owned
    |> Ecto.Multi.run(:fetch_existing, fn _repo, _changes -> {:ok, get_all_minor_leaguers()} end)
    # (2) filter the incoming list into 3 lists of `search_key_without_owner`, this will give us the data
    # to set up the changesets for the next few steps
    |> Ecto.Multi.run(
      :calculate_diffs,
      fn _repo, %{fetch_existing: existing_players} ->
        {incoming_minor_leaguers_not_yet_in_db, players_in_db_but_not_in_sheets,
         players_with_new_owners, existing_map_without_owners,
         incoming_map_without_owners} =
          calculate_diff_from_incoming_prospects(incoming_minor_leaguers, existing_players)

        {
          :ok,
          [
            players_to_insert: incoming_minor_leaguers_not_yet_in_db,
            players_to_clear: players_in_db_but_not_in_sheets,
            players_to_update: players_with_new_owners,
            existing_player_map: existing_map_without_owners,
            incoming_player_map: incoming_map_without_owners
          ]
        }
      end
    )
    # (3) use the mapsets from step (2) to build changesets that are either entries to insert or update in the db
    |> Ecto.Multi.run(
      :build_upsert_list,
      fn _repo,
         %{
           calculate_diffs: [
             players_to_insert: mapset_of_search_keys_to_insert,
             players_to_clear: _,
             players_to_update: mapset_of_search_keys_to_update,
             existing_player_map: existing_player_map,
             incoming_player_map: incoming_player_map
           ]
         } ->
        changesets =
          build_upsert_list(
            mapset_of_search_keys_to_insert,
            mapset_of_search_keys_to_update,
            incoming_player_map,
            existing_player_map
          )

        {:ok, [changesets_to_upsert: changesets]}
      end
    )
    # (4) run the upsert transaction
    |> Ecto.Multi.run(
      :upsert,
      fn repo,
         %{
           build_upsert_list: [changesets_to_upsert: changesets_to_upsert]
         } ->
        results = Enum.map(changesets_to_upsert, fn cs -> repo.insert_or_update(cs) end)
        {:ok, results}
      end
    )
    # (5) update existing players not found in the sheet to unset the league_team_id field
    |> Ecto.Multi.update_all(
      :unset_existing_player_teams,
      fn %{
           calculate_diffs: [
             players_to_insert: _,
             players_to_clear: players_to_clear_ownership,
             players_to_update: _,
             existing_player_map: existing_player_map,
             incoming_player_map: _
           ]
         } ->
        ids =
          Enum.map(players_to_clear_ownership, fn search_key ->
            Map.get(existing_player_map, search_key)
            |> Map.get(:id)
          end)

        Logger.debug("Final multi step")

        Player
        |> Ecto.Query.where([p], p.id in ^ids)
      end,
      set: [
        leagueTeamId: nil
      ]
    )
    |> TradeMachine.Repo.transaction()
  end

  ## Private
  @spec calculate_diff_from_incoming_prospects(
          list(IncomingMinorLeaguer.t()),
          list(__MODULE__.t())
        ) ::
          {MapSet.t(String.t()), MapSet.t(String.t()), list(String.t()),
           %{String.t() => __MODULE__.t()}, %{String.t() => IncomingMinorLeaguer.t()}}
  defp calculate_diff_from_incoming_prospects(incoming_minor_leaguers, existing_players) do
    {mapset_incoming_minor_leaguers_no_owners, incoming_map_without_owners} =
      generate_mapsets(incoming_minor_leaguers)

    {mapset_existing_minor_leaguers_no_owners, existing_map_without_owners} =
      generate_mapsets(existing_players)

    # These prospects from the sheet are not found in the db with the same name+league+level+mlb_team+position;
    # So regardless of owner, they don't exist in db and need to be `inserted`
    incoming_minor_leaguers_not_yet_in_db =
      MapSet.difference(
        mapset_incoming_minor_leaguers_no_owners,
        mapset_existing_minor_leaguers_no_owners
      )

    # These players in the db are not found in the sheet with the same name+league+level+mlb_team+position;
    # So regardless of owner, they don't exist the sheet so they are no longer 'actively owned minors' and
    # the owner field for this player should be cleared
    players_in_db_but_not_in_sheets =
      MapSet.difference(
        mapset_existing_minor_leaguers_no_owners,
        mapset_incoming_minor_leaguers_no_owners
      )

    # First find the union of players whose name+league+level+mlb_team+position exists in both the sheet and the db
    # Then filter out the ones that have the same owner in the sheet as in the db
    # The remainder will be the players that we need to update the owners of
    players_with_new_owners =
      MapSet.intersection(
        mapset_incoming_minor_leaguers_no_owners,
        mapset_existing_minor_leaguers_no_owners
      )
      |> Enum.reject(fn same_player_key ->
        player_in_db = Map.get(existing_map_without_owners, same_player_key)
        player_in_sheet = Map.get(incoming_map_without_owners, same_player_key)
        player_in_db.owned_by.id == player_in_sheet.owner_id
      end)

    {incoming_minor_leaguers_not_yet_in_db, players_in_db_but_not_in_sheets,
     players_with_new_owners, existing_map_without_owners, incoming_map_without_owners}
  end

  @spec search_key_without_owner(
          __MODULE__.t()
          | %{
              league: atom(),
              name: String.t(),
              position: String.t(),
              mlb_team: String.t(),
              league_level: String.t(),
              owned_by: String.t()
            }
        ) :: search_key()
  defp search_key_without_owner(player = %__MODULE__{}) do
    "#{player.name};#{player.league};#{player.meta["minorLeaguePlayerFromSheet"]["position"]};" <>
      "#{player.meta["minorLeaguePlayerFromSheet"]["leagueLevel"]};" <>
      "#{player.meta["minorLeaguePlayerFromSheet"]["mlbTeam"]}"
  end

  defp search_key_without_owner(player) when is_map(player) do
    "#{player.name};#{player.league};#{player.position};#{player.league_level};#{player.mlb_team}"
  end

  @spec generate_mapsets(list(__MODULE__.t() | IncomingMinorLeaguer.t())) ::
          {MapSet.t(String.t()), %{String.t() => __MODULE__.t() | IncomingMinorLeaguer.t()}}
  defp generate_mapsets(prospects) do
    Enum.reduce(prospects, {MapSet.new(), Map.new()}, fn prospect,
                                                         {mapset_without_owners,
                                                          map_without_owners} ->
      search_key_without_owner = search_key_without_owner(prospect)

      {
        MapSet.put(mapset_without_owners, search_key_without_owner),
        Map.put(map_without_owners, search_key_without_owner, prospect)
      }
    end)
  end

  @spec build_upsert_list(
          MapSet.t(String.t()),
          MapSet.t(String.t()),
          %{String.t() => IncomingMinorLeaguer.t()},
          %{String.t() => __MODULE__.t()}
        ) :: list(Ecto.Changeset.t(__MODULE__.t()))
  defp build_upsert_list(
         mapset_of_search_keys_to_insert,
         mapset_of_search_keys_to_update,
         incoming_player_map,
         existing_player_map
       ) do
    changesets_to_insert =
      Enum.map(mapset_of_search_keys_to_insert, fn search_key ->
        incoming_player = Map.get(incoming_player_map, search_key)
        new(incoming_player_to_map(incoming_player))
      end)

    changesets_to_update =
      Enum.map(mapset_of_search_keys_to_update, fn search_key ->
        player_to_update = Map.get(existing_player_map, search_key)
        incoming_player = Map.get(incoming_player_map, search_key)
        new_owner = incoming_player.owned_by
        changeset(player_to_update, %{leagueTeamId: new_owner})
      end)

    changesets_to_insert ++ changesets_to_update
  end

  @spec incoming_player_to_map(IncomingMinorLeaguer.t()) :: map()
  defp incoming_player_to_map(incoming_player) do
    %{
      name: incoming_player.name,
      league: incoming_player.league,
      mlb_team: incoming_player.mlb_team,
      meta: %{
        "minorLeaguePlayerFromSheet" => %{
          "position" => incoming_player.position,
          "leagueLevel" => incoming_player.league_level,
          "mlbTeam" => incoming_player.mlb_team
        }
      }
    }
  end
end
