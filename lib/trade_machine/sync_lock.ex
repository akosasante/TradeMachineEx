defmodule TradeMachine.SyncLock do
  @moduledoc """
  Node-level mutual exclusion for long-running sync operations.

  Prevents concurrent execution of the same sync job regardless of whether
  it was triggered via Oban cron, Oban retry/rescue, or a manual IEx call.

  The lock is tied to the caller's pid via `Process.monitor/1`, so it is
  automatically released if the caller crashes.

  ## Usage

      case SyncLock.acquire(:mlb_players_sync) do
        :acquired ->
          try do
            do_expensive_sync()
          after
            SyncLock.release(:mlb_players_sync)
          end

        {:already_running, acquired_at} ->
          Logger.warning("Sync already running since \#{acquired_at}")
      end

  ## Inspection

      iex> TradeMachine.SyncLock.status()
      %{mlb_players_sync: %{pid: #PID<0.456.0>, acquired_at: ~U[2026-03-02 19:14:20Z]}}
  """

  use GenServer
  require Logger

  # -- Client API ------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.merge([name: __MODULE__], opts))
  end

  @doc "Attempt to acquire a named lock. Returns `:acquired` or `{:already_running, acquired_at}`."
  @spec acquire(atom()) :: :acquired | {:already_running, DateTime.t()}
  def acquire(job_name) when is_atom(job_name) do
    GenServer.call(__MODULE__, {:acquire, job_name})
  end

  @doc "Release a previously acquired lock."
  @spec release(atom()) :: :ok
  def release(job_name) when is_atom(job_name) do
    GenServer.call(__MODULE__, {:release, job_name})
  end

  @doc "Force-release a lock regardless of who holds it. Use from IEx when a lock is stuck."
  @spec force_release(atom()) :: :ok
  def force_release(job_name) when is_atom(job_name) do
    GenServer.call(__MODULE__, {:force_release, job_name})
  end

  @doc "Return current lock state for inspection."
  @spec status() :: %{atom() => %{pid: pid(), acquired_at: DateTime.t()}}
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # -- Server callbacks ------------------------------------------------------

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:acquire, job_name}, {caller_pid, _}, state) do
    case Map.get(state, job_name) do
      nil ->
        ref = Process.monitor(caller_pid)

        entry = %{pid: caller_pid, monitor_ref: ref, acquired_at: DateTime.utc_now()}
        {:reply, :acquired, Map.put(state, job_name, entry)}

      %{acquired_at: acquired_at} ->
        {:reply, {:already_running, acquired_at}, state}
    end
  end

  def handle_call({:release, job_name}, {caller_pid, _}, state) do
    case Map.get(state, job_name) do
      %{pid: ^caller_pid, monitor_ref: ref} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, Map.delete(state, job_name)}

      %{pid: other_pid} ->
        Logger.warning(
          "SyncLock.release(#{job_name}) called by #{inspect(caller_pid)} " <>
            "but lock is held by #{inspect(other_pid)}, ignoring"
        )

        {:reply, :ok, state}

      nil ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:force_release, job_name}, _from, state) do
    case Map.get(state, job_name) do
      %{monitor_ref: ref} ->
        Process.demonitor(ref, [:flush])
        Logger.warning("SyncLock: force-released #{job_name}")
        {:reply, :ok, Map.delete(state, job_name)}

      nil ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:status, _from, state) do
    public =
      Map.new(state, fn {k, %{pid: pid, acquired_at: at}} ->
        {k, %{pid: pid, acquired_at: at}}
      end)

    {:reply, public, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Enum.find(state, fn {_k, %{monitor_ref: r}} -> r == ref end) do
      {job_name, _entry} ->
        Logger.warning(
          "SyncLock: auto-releasing #{job_name} — holder #{inspect(pid)} exited (#{inspect(reason)})"
        )

        {:noreply, Map.delete(state, job_name)}

      nil ->
        {:noreply, state}
    end
  end
end
