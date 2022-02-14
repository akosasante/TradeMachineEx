defmodule TradeMachine.Data.Player do
  defmodule IncomingMinorLeaguer do
    use Ecto.Schema
    require Logger

    embedded_schema do
      field :name, :string

      field :league,
            Ecto.Enum,
            values: [
              minor: "2"
            ]

      # TODO can this be DRY-ed?
      field :owner_id, Ecto.UUID
      # TODO We can make this Enum probably
      field :position, :string
      field :mlb_team, :string
      field :league_level, :string
    end
  end

  use TradeMachine.Schema

  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Player.IncomingMinorLeaguer
  alias TradeMachine.Data.Team

  require Ecto.Query
  require Logger

  @required_fields [:name, :league]
  @optional_fields [:mlb_team, :player_data_id, :meta, :leagueTeamId]

  schema "player" do
    field :name, :string

    field :league,
          Ecto.Enum,
          values: [
            major: "1",
            minor: "2"
          ]

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

  def get_all_minor_leaguers() do
    __MODULE__
    # TODO: maybe import ecto.query so we don't need all this
    |> Ecto.Query.where(
      [p],
      p.league == :minor and not is_nil(p.leagueTeamId) and not is_nil(p.meta)
    )
    # TODO Potentially make this part optional
    |> Ecto.Query.preload(:owned_by)
    # TODO: Potentially make this part optional
    |> Ecto.Query.select([p], %Player{p | meta: p.meta})
    # TODO This is just for testing
    #    |> Ecto.Query.limit(5)
    # TODO: maybe alias here
    |> TradeMachine.Repo.all()
  end

  def batch_insert_minor_leaguers(incoming_major_leaguers) do
    Ecto.Multi.new()
    # (1) fetch current minor leaguers that are owned
    |> Ecto.Multi.run(
      :fetch_existing,
      fn _repo, _changes ->
        {:ok, get_all_minor_leaguers()}
      end
    )
    # (2) filter the incoming list: drop entries from both that have the same name+league+mlb_team+position+owner as in the db; no change needed
    |> Ecto.Multi.run(
      :drop_existing_entries,
      fn _repo, %{fetch_existing: existing_players} ->
        changeset_list_with_fields_of_interest =
          Enum.map(
            incoming_major_leaguers,
            fn %IncomingMinorLeaguer{
                 league: league,
                 name: name,
                 position: position,
                 owner_id: owner_id,
                 mlb_team: mlb_team,
                 league_level: league_level
               } ->
              %{
                name: name,
                league: league,
                position: position,
                mlb_team: mlb_team,
                league_level: league_level,
                owned_by: owner_id
              }
            end
          )
          |> MapSet.new()

        existing_list_with_fields_of_interest =
          Enum.map(
            existing_players,
            fn %__MODULE__{
                 league: league,
                 name: name,
                 owned_by: %Team{
                   id: owner_id
                 },
                 meta: %{
                   "minorLeaguePlayerFromSheet" => %{
                     "position" => position,
                     "mlbTeam" => mlb_team,
                     "leagueLevel" => league_level
                   }
                 }
               } ->
              %{
                name: name,
                league: league,
                position: position,
                mlb_team: mlb_team,
                league_level: league_level,
                owned_by: owner_id
              }
            end
          )
          |> MapSet.new()

        filtered_list_of_players =
          MapSet.difference(
            changeset_list_with_fields_of_interest,
            existing_list_with_fields_of_interest
          )

        players_to_clear_ownership =
          MapSet.difference(
            existing_list_with_fields_of_interest,
            changeset_list_with_fields_of_interest
          )
          |> then(fn player_maps_to_filter ->
            Enum.filter(
              existing_players,
              &Enum.member?(
                player_maps_to_filter,
                %{
                  name: &1.name,
                  league: &1.league,
                  owned_by: &1.owned_by.id,
                  position: &1.meta["minorLeaguePlayerFromSheet"]["position"],
                  league_level: &1.meta["minorLeaguePlayerFromSheet"]["leagueLevel"],
                  mlb_team: &1.meta["minorLeaguePlayerFromSheet"]["mlbTeam"]
                }
              )
            )
          end)

        {
          :ok,
          [
            players_to_upsert: filtered_list_of_players,
            players_to_clear: players_to_clear_ownership
          ]
        }
      end
    )
    # (3) build a list of entries that have the same name+league+mlb_team+position, but different owner. Only the owner needs to be updated; filter the db list.
    |> Ecto.Multi.run(
      :build_upsert_list,
      fn _repo,
         %{
           fetch_existing: existing_players,
           drop_existing_entries: [
             players_to_upsert: list_of_players_to_upsert,
             players_to_clear: list_of_players_to_clear
           ]
         } ->
        {changesets, players_to_clear} =
          Enum.reduce(
            list_of_players_to_upsert,
            {[], list_of_players_to_clear},
            fn player, acc ->
              {cs, updated_players_to_clear} =
                case Enum.find(
                       existing_players,
                       fn existing_player ->
                         existing_player.name == player.name and
                           existing_player.league == player.league and
                           get_in(
                             existing_player,
                             [
                               Access.key(:meta, %{}),
                               Access.key("minorLeaguePlayerFromSheet", %{}),
                               Access.key("position")
                             ]
                           ) ==
                             player.position and
                           get_in(
                             existing_player,
                             [
                               Access.key(:meta, %{}),
                               Access.key("minorLeaguePlayerFromSheet", %{}),
                               Access.key("mlbTeam")
                             ]
                           ) == player.mlb_team and
                           get_in(
                             existing_player,
                             [
                               Access.key(:meta, %{}),
                               Access.key("minorLeaguePlayerFromSheet", %{}),
                               Access.key("leagueLevel")
                             ]
                           ) == player.league_level
                       end
                     ) do
                  %__MODULE__{} = matching_existing_player ->
                    Logger.debug(
                      "Found a matching existing player: #{player.name} vs #{matching_existing_player.name}. Just gonna update the league team id"
                    )

                    cs =
                      changeset(
                        matching_existing_player,
                        player
                        |> Map.put(:leagueTeamId, player.owned_by)
                      )

                    {cs, Enum.reject(elem(acc, 1), &(&1 == matching_existing_player))}

                  nil ->
                    Logger.debug("Did not find a matching player for #{inspect(player)}")

                    cs =
                      new(
                        player
                        |> Map.put(:leagueTeamId, player.owned_by)
                        |> Map.put(
                          :meta,
                          %{
                            "minorLeaguePlayerFromSheet" => %{
                              "position" => player.position,
                              "mlbTeam" => player.mlb_team,
                              "leagueLevel" => player.league_level
                            }
                          }
                        )
                      )

                    {cs, elem(acc, 1)}
                end

              {[cs | elem(acc, 0)], updated_players_to_clear}
            end
          )

        {:ok, [changesets_to_upsert: changesets, players_to_clear: players_to_clear]}
      end
    )
    # (3a) update in db
    |> Ecto.Multi.run(
      :upsert,
      fn repo,
         %{
           build_upsert_list: [
             changesets_to_upsert: changesets_to_upsert,
             players_to_clear: _
           ]
         } ->
        results = Enum.map(changesets_to_upsert, fn cs -> repo.insert_or_update(cs) end)
        {:ok, results}
      end
    )
    # (3b) update existing players to unset the league_team_id field
    |> Ecto.Multi.update_all(
      :unset_existing_player_teams,
      fn %{
           build_upsert_list: [
             changesets_to_upsert: _,
             players_to_clear: players_to_clear
           ]
         } ->
        ids = Enum.map(players_to_clear, & &1.id)

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
end
