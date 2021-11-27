defmodule TradeMachine.Data.Player do
  defmodule IncomingMinorLeaguer do
    use Ecto.Schema

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
    end
  end

  use TradeMachine.Schema

  alias TradeMachine.Data.Player
  alias TradeMachine.Data.Player.IncomingMinorLeaguer
  alias TradeMachine.Data.Team

  require Ecto.Query

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

  def new_changeset(params \\ %{}) do
    changeset(%__MODULE__{}, params)
  end

  def changeset(struct = %__MODULE__{}, params \\ %{}) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def group_by_validity(list_of_maps) do
    list_of_maps
    |> Enum.map(fn m -> new_changeset(m) end)
    |> Enum.group_by(& &1.valid?)
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
    |> Ecto.Query.limit(5)
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
                    mlb_team: mlb_team
                  } ->
                 %{name: name, league: league, position: position, mlb_team: mlb_team, owned_by: owner_id}
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
                        "mlbTeam" => mlb_team
                      }
                    }
                  } ->
                 %{name: name, league: league, position: position, mlb_team: mlb_team, owned_by: owner_id}
               end
             )
             |> MapSet.new()

           filtered_list_of_players =
             MapSet.difference(
               changeset_list_with_fields_of_interest,
               existing_list_with_fields_of_interest
             )

           {:ok, filtered_list_of_players}
         end
       )
      # (3) build a list of entries that have the same name+league+mlb_team+position, but different owner. Only the owner needs to be updated; filter the db list.
    |> Ecto.Multi.run(
         :build_upsert_list,
         fn _repo,
            %{fetch_existing: existing_players, drop_existing_entries: list_of_players_to_upsert} ->
           changesets = Enum.reduce(
             list_of_players_to_upsert,
             [],
             fn player, acc ->
               cs = case Enum.find(
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
                             ) == player.mlb_team
                           end
                         ) do
                 %__MODULE__{} = matching_existing_player ->
                   IO.puts "Found a matching existing player: #{player.name} vs #{
                     matching_existing_player.name
                   }. Just gonna update the league team id"
                   changeset(
                     matching_existing_player,
                     player
                     |> Map.put(:leagueTeamId, player.owned_by)
                   )

                 nil ->
                   IO.puts "Did not find a matching player for #{inspect(player)}"
                   new_changeset(
                     player
                     |> Map.put(:leagueTeamId, player.owned_by)
                     |> Map.put(
                          :meta,
                          %{
                            "minorLeaguePlayerFromSheet" => %{
                              "position" => player.position,
                              "mlbTeam" => player.mlb_team
                            }
                          }
                        )
                   )
               end

               [cs | acc]
             end
           )

           {:ok, changesets}
         end
       )
      # (3a) update in db
    |> Ecto.Multi.run(
         :upsert,
         fn repo, %{build_upsert_list: changesets_to_upsert} ->
           results = Enum.map(changesets_to_upsert, fn cs -> repo.insert_or_update(cs) end)
           {:ok, results}
         end
       )
    |> TradeMachine.Repo.transaction()
  end
end
