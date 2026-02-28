defmodule TradeMachine.SyncTracking do
  @moduledoc """
  Context module for tracking sync job executions.

  Provides functions to record when Oban sync jobs start, complete, or fail,
  along with metrics about records processed. Supports querying sync history
  to answer questions like "when did ESPN teams last sync successfully?"
  """

  import Ecto.Query
  require Logger

  alias TradeMachine.Data.SyncJobExecution

  @doc """
  Records the start of a sync job execution.

  Returns the created `SyncJobExecution` record that should be passed to
  `complete_sync/3` or `fail_sync/3` when the job finishes.
  """
  @spec start_sync(SyncJobExecution.job_type(), SyncJobExecution.database_scope(), keyword()) ::
          {:ok, SyncJobExecution.t()} | {:error, Ecto.Changeset.t()}
  def start_sync(job_type, database_scope, opts \\ []) do
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)

    params = %{
      job_type: job_type,
      database_scope: database_scope,
      status: :started,
      started_at: DateTime.utc_now(),
      oban_job_id: Keyword.get(opts, :oban_job_id),
      trace_id: Keyword.get(opts, :trace_id),
      metadata: Keyword.get(opts, :metadata)
    }

    %SyncJobExecution{}
    |> SyncJobExecution.changeset(params)
    |> repo.insert()
  end

  @doc """
  Marks a sync job execution as completed with metrics.

  `metrics` is a map that may include:
  - `:records_processed` - total records fetched/processed
  - `:records_updated` - successfully updated records
  - `:records_skipped` - skipped records
  - `:metadata` - additional job-specific data to merge
  """
  @spec complete_sync(SyncJobExecution.t(), map(), keyword()) ::
          {:ok, SyncJobExecution.t()} | {:error, Ecto.Changeset.t()}
  def complete_sync(execution = %SyncJobExecution{}, metrics \\ %{}, opts \\ []) do
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)
    now = DateTime.utc_now()
    duration_ms = DateTime.diff(now, execution.started_at, :millisecond)

    merged_metadata =
      case {execution.metadata, Map.get(metrics, :metadata)} do
        {nil, nil} -> nil
        {existing, nil} -> existing
        {nil, new} -> new
        {existing, new} -> Map.merge(existing, new)
      end

    params = %{
      status: :completed,
      completed_at: now,
      duration_ms: duration_ms,
      records_processed: Map.get(metrics, :records_processed),
      records_updated: Map.get(metrics, :records_updated),
      records_skipped: Map.get(metrics, :records_skipped),
      metadata: merged_metadata
    }

    execution
    |> SyncJobExecution.changeset(params)
    |> repo.update()
  end

  @doc """
  Marks a sync job execution as failed with an error message.
  """
  @spec fail_sync(SyncJobExecution.t(), String.t(), keyword()) ::
          {:ok, SyncJobExecution.t()} | {:error, Ecto.Changeset.t()}
  def fail_sync(execution = %SyncJobExecution{}, error_message, opts \\ []) do
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)
    now = DateTime.utc_now()
    duration_ms = DateTime.diff(now, execution.started_at, :millisecond)

    params = %{
      status: :failed,
      completed_at: now,
      duration_ms: duration_ms,
      error_message: error_message
    }

    execution
    |> SyncJobExecution.changeset(params)
    |> repo.update()
  end

  @doc """
  Returns the most recent successful sync for a given job type and database scope.
  """
  @spec get_last_sync(SyncJobExecution.job_type(), SyncJobExecution.database_scope(), keyword()) ::
          SyncJobExecution.t() | nil
  def get_last_sync(job_type, database_scope, opts \\ []) do
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)

    SyncJobExecution
    |> where([s], s.job_type == ^job_type)
    |> where([s], s.database_scope == ^database_scope)
    |> where([s], s.status == :completed)
    |> order_by([s], desc: s.started_at)
    |> limit(1)
    |> repo.one()
  end

  @doc """
  Returns recent sync history for a given job type, optionally filtered by database scope.

  ## Options
  - `:repo` - Ecto repo to query (default: `TradeMachine.Repo.Production`)
  - `:days` - number of days of history to return (default: 7)
  - `:limit` - max number of records (default: 50)
  """
  @spec get_sync_history(
          SyncJobExecution.job_type(),
          SyncJobExecution.database_scope() | nil,
          keyword()
        ) ::
          [SyncJobExecution.t()]
  def get_sync_history(job_type, database_scope \\ nil, opts \\ []) do
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)
    days = Keyword.get(opts, :days, 7)
    result_limit = Keyword.get(opts, :limit, 50)
    cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

    query =
      SyncJobExecution
      |> where([s], s.job_type == ^job_type)
      |> where([s], s.started_at >= ^cutoff)
      |> order_by([s], desc: s.started_at)
      |> limit(^result_limit)

    query =
      if database_scope do
        where(query, [s], s.database_scope == ^database_scope)
      else
        query
      end

    repo.all(query)
  end

  @doc """
  Returns any failed syncs within the given time window.

  ## Options
  - `:repo` - Ecto repo to query (default: `TradeMachine.Repo.Production`)
  - `:hours` - number of hours to look back (default: 24)
  """
  @spec get_recent_failures(keyword()) :: [SyncJobExecution.t()]
  def get_recent_failures(opts \\ []) do
    repo = Keyword.get(opts, :repo, TradeMachine.Repo.Production)
    hours = Keyword.get(opts, :hours, 24)
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 60 * 60, :second)

    SyncJobExecution
    |> where([s], s.status == :failed)
    |> where([s], s.started_at >= ^cutoff)
    |> order_by([s], desc: s.started_at)
    |> repo.all()
  end
end
