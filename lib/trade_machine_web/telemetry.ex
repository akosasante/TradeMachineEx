defmodule TradeMachineWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      # PromEx for Prometheus metrics collection
      TradeMachine.PromEx
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        tags: [:method, :route]
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      counter("phoenix.endpoint.stop.duration",
        tags: [:method, :status_class],
        tag_values: &get_status_class/1
      ),

      # Database Metrics
      summary("trade_machine.repo.query.total_time",
        unit: {:native, :millisecond},
        tags: [:source, :command]
      ),
      summary("trade_machine.repo.query.decode_time",
        unit: {:native, :millisecond},
        tags: [:source, :command]
      ),
      summary("trade_machine.repo.query.query_time",
        unit: {:native, :millisecond},
        tags: [:source, :command]
      ),
      summary("trade_machine.repo.query.queue_time",
        unit: {:native, :millisecond},
        tags: [:source, :command]
      ),
      counter("trade_machine.repo.query.count",
        tags: [:source, :command, :result]
      ),

      # Oban Job Metrics (Custom business metrics)
      counter("oban.job.count",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        tags: [:worker, :queue, :state]
      ),
      summary("oban.job.duration",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:worker, :queue, :state]
      ),
      summary("oban.job.queue_time",
        event_name: [:oban, :job, :stop],
        measurement: :queue_time,
        unit: {:native, :millisecond},
        tags: [:worker, :queue]
      ),

      # Google Sheets API Metrics
      counter("trade_machine.sheets_api.requests",
        tags: [:operation, :status]
      ),
      summary("trade_machine.sheets_api.duration",
        unit: {:native, :millisecond},
        tags: [:operation, :status]
      ),

      # VM and System Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.memory.processes", unit: {:byte, :kilobyte}),
      summary("vm.memory.atom", unit: {:byte, :kilobyte}),
      summary("vm.memory.ets", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),
      last_value("vm.process_count"),
      last_value("vm.port_count")
    ]
  end

  defp periodic_measurements do
    [
      # VM measurements
      {__MODULE__, :dispatch_vm_stats, []}
      # Custom business metrics
      #      {__MODULE__, :dispatch_oban_stats, []},
      # Google Sheets connection health
      #      {__MODULE__, :dispatch_sheets_health, []}
    ]
  end

  # Custom measurement functions
  def dispatch_vm_stats do
    memory_stats = :erlang.memory()

    # Get total run queue lengths (single integer)
    total_run_queues = :erlang.statistics(:total_run_queue_lengths)

    :telemetry.execute([:vm], %{
      memory: %{
        total: memory_stats[:total],
        processes: memory_stats[:processes],
        atom: memory_stats[:atom],
        ets: memory_stats[:ets]
      },
      total_run_queue_lengths: %{
        total: total_run_queues
      },
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count)
    })
  end

  def dispatch_oban_stats do
    try do
      # Get Oban queue stats if available
      stats = Oban.check_queue(TradeMachine.Repo, queue: "minors_sync")
      :telemetry.execute([:oban, :queue, :stats], stats, %{queue: "minors_sync"})

      stats = Oban.check_queue(TradeMachine.Repo, queue: "draft_sync")
      :telemetry.execute([:oban, :queue, :stats], stats, %{queue: "draft_sync"})
    rescue
      error ->
        Logger.debug("Failed to get Oban stats: #{inspect(error)}")
    end
  end

  def dispatch_sheets_health do
    try do
      # Simple health check for Google Sheets connectivity
      case Process.whereis(TradeMachine.SheetReader) do
        pid when is_pid(pid) ->
          :telemetry.execute([:sheets, :health], %{status: 1}, %{component: "sheet_reader"})

        nil ->
          :telemetry.execute([:sheets, :health], %{status: 0}, %{component: "sheet_reader"})
      end

      case Process.whereis(TradeMachine.Goth) do
        pid when is_pid(pid) ->
          :telemetry.execute([:sheets, :health], %{status: 1}, %{component: "goth"})

        nil ->
          :telemetry.execute([:sheets, :health], %{status: 0}, %{component: "goth"})
      end
    rescue
      error ->
        Logger.debug("Failed to check sheets health: #{inspect(error)}")
        :telemetry.execute([:sheets, :health], %{status: 0}, %{component: "error"})
    end
  end

  # Helper function to categorize HTTP status codes
  defp get_status_class(%{status: status}) when status < 400, do: %{status_class: "2xx_3xx"}
  defp get_status_class(%{status: status}) when status < 500, do: %{status_class: "4xx"}
  defp get_status_class(%{status: _status}), do: %{status_class: "5xx"}
  defp get_status_class(_), do: %{status_class: "unknown"}
end
