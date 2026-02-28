defmodule TradeMachine.Data.SyncJobExecution do
  @moduledoc """
  Tracks execution history of Oban sync jobs (ESPN team sync, minors sync, etc.).

  Provides a persistent record of when each sync ran, its status, and metrics
  like records processed/updated/skipped. Used to answer questions like
  "when did the last ESPN sync run?" and "did it succeed?"
  """

  use TradeMachine.Schema

  @type job_type :: :espn_team_sync | :minors_sync | :mlb_players_sync | :draft_picks_sync
  @type database_scope :: :production | :staging | :both
  @type sync_status :: :started | :completed | :failed

  typed_schema "sync_job_execution" do
    field(:job_type, Ecto.Enum,
      values: [:espn_team_sync, :minors_sync, :mlb_players_sync, :draft_picks_sync],
      null: false
    )

    field(:database_scope, Ecto.Enum,
      values: [:production, :staging, :both],
      null: false
    )

    field(:status, Ecto.Enum,
      values: [:started, :completed, :failed],
      null: false
    )

    field(:started_at, :utc_datetime_usec, null: false)
    field(:completed_at, :utc_datetime_usec)
    field(:duration_ms, :integer)

    field(:records_processed, :integer)
    field(:records_updated, :integer)
    field(:records_skipped, :integer)

    field(:error_message, :string)

    field(:oban_job_id, :integer)
    field(:trace_id, :string)
    field(:metadata, :map)

    timestamps()
  end

  @required_fields [:job_type, :database_scope, :status, :started_at]
  @optional_fields [
    :completed_at,
    :duration_ms,
    :records_processed,
    :records_updated,
    :records_skipped,
    :error_message,
    :oban_job_id,
    :trace_id,
    :metadata
  ]

  def changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
