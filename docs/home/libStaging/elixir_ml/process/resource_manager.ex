defmodule ElixirML.Process.ResourceManager do
  @moduledoc """
  Manages system resources including memory, process limits, and cleanup.
  Provides resource monitoring and automatic cleanup for long-running processes.
  """

  use GenServer
  require Logger

  defstruct [
    :max_memory_mb,
    :max_processes,
    :cleanup_interval_ms,
    :current_memory_usage,
    :current_process_count,
    :resource_history,
    :alerts
  ]

  # 1GB
  @default_max_memory_mb 1024
  @default_max_processes 100
  # 1 minute
  @default_cleanup_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    state = %__MODULE__{
      max_memory_mb: Keyword.get(opts, :max_memory_mb, @default_max_memory_mb),
      max_processes: Keyword.get(opts, :max_processes, @default_max_processes),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      current_memory_usage: 0,
      current_process_count: 0,
      resource_history: [],
      alerts: []
    }

    # Schedule periodic cleanup and monitoring
    schedule_cleanup(state.cleanup_interval_ms)
    # Monitor every 5 seconds
    schedule_monitoring(5000)

    {:ok, state}
  end

  @doc """
  Get current resource usage statistics.
  """
  def get_resource_stats do
    GenServer.call(__MODULE__, :get_resource_stats)
  end

  @doc """
  Check if system has available resources for a new operation.
  """
  def check_resource_availability(resource_requirements \\ %{}) do
    GenServer.call(__MODULE__, {:check_availability, resource_requirements})
  end

  @doc """
  Request resource allocation for a process.
  """
  def allocate_resources(pid, resource_spec) do
    GenServer.call(__MODULE__, {:allocate_resources, pid, resource_spec})
  end

  @doc """
  Release resources when a process terminates.
  """
  def release_resources(pid) do
    GenServer.cast(__MODULE__, {:release_resources, pid})
  end

  @doc """
  Force cleanup of idle resources.
  """
  def force_cleanup do
    GenServer.cast(__MODULE__, :force_cleanup)
  end

  @doc """
  Get resource usage history.
  """
  def get_resource_history(limit \\ 100) do
    GenServer.call(__MODULE__, {:get_resource_history, limit})
  end

  # Server callbacks

  def handle_call(:get_resource_stats, _from, state) do
    stats = %{
      memory_usage_mb: state.current_memory_usage,
      max_memory_mb: state.max_memory_mb,
      memory_utilization: state.current_memory_usage / state.max_memory_mb,
      process_count: state.current_process_count,
      max_processes: state.max_processes,
      process_utilization: state.current_process_count / state.max_processes,
      active_alerts: length(state.alerts),
      erlang_memory: get_erlang_memory_stats()
    }

    {:reply, stats, state}
  end

  def handle_call({:check_availability, requirements}, _from, state) do
    required_memory = Map.get(requirements, :memory_mb, 0)
    required_processes = Map.get(requirements, :processes, 1)

    memory_available = state.current_memory_usage + required_memory <= state.max_memory_mb
    processes_available = state.current_process_count + required_processes <= state.max_processes

    availability = %{
      memory_available: memory_available,
      processes_available: processes_available,
      can_allocate: memory_available and processes_available,
      current_memory_usage: state.current_memory_usage,
      current_process_count: state.current_process_count
    }

    {:reply, availability, state}
  end

  def handle_call({:allocate_resources, pid, resource_spec}, _from, state) do
    # Handle nil resource_spec gracefully
    resource_spec = resource_spec || %{}
    memory_required = Map.get(resource_spec, :memory_mb, 0)

    if state.current_memory_usage + memory_required <= state.max_memory_mb and
         state.current_process_count + 1 <= state.max_processes do
      # Monitor the process
      Process.monitor(pid)

      new_state = %{
        state
        | current_memory_usage: state.current_memory_usage + memory_required,
          current_process_count: state.current_process_count + 1
      }

      {:reply, {:ok, :allocated}, new_state}
    else
      {:reply, {:error, :insufficient_resources}, state}
    end
  end

  def handle_call({:get_resource_history, limit}, _from, state) do
    history =
      state.resource_history
      |> Enum.take(limit)

    {:reply, history, state}
  end

  def handle_cast({:release_resources, _pid}, state) do
    # In a real implementation, we'd track per-process resource usage
    # For now, just decrement process count
    new_state = %{state | current_process_count: max(0, state.current_process_count - 1)}

    {:noreply, new_state}
  end

  def handle_cast(:force_cleanup, state) do
    new_state = perform_cleanup(state)
    {:noreply, new_state}
  end

  def handle_info(:monitor_resources, state) do
    # Update current resource usage
    erlang_memory = get_erlang_memory_stats()
    current_memory_mb = erlang_memory.total / (1024 * 1024)

    # Record history
    history_entry = %{
      timestamp: System.monotonic_time(:millisecond),
      memory_usage_mb: current_memory_mb,
      process_count: state.current_process_count,
      erlang_stats: erlang_memory
    }

    new_history = [history_entry | state.resource_history] |> Enum.take(1000)

    # Check for alerts
    new_alerts = check_resource_alerts(state, current_memory_mb)

    new_state = %{
      state
      | current_memory_usage: current_memory_mb,
        resource_history: new_history,
        alerts: new_alerts
    }

    # Schedule next monitoring
    schedule_monitoring(5000)

    {:noreply, new_state}
  end

  def handle_info(:cleanup_resources, state) do
    new_state = perform_cleanup(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Process terminated, release its resources
    new_state = %{state | current_process_count: max(0, state.current_process_count - 1)}

    {:noreply, new_state}
  end

  # Private functions

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_resources, interval)
  end

  defp schedule_monitoring(interval) do
    Process.send_after(self(), :monitor_resources, interval)
  end

  defp perform_cleanup(state) do
    # Force garbage collection
    :erlang.garbage_collect()

    # Clean up ETS tables if they exist
    cleanup_ets_tables()

    # Clear old alerts
    now = System.monotonic_time(:millisecond)
    five_minutes_ago = now - 5 * 60 * 1000

    new_alerts =
      Enum.filter(state.alerts, fn alert ->
        alert.timestamp > five_minutes_ago
      end)

    Logger.info(
      "Resource cleanup completed. Cleared #{length(state.alerts) - length(new_alerts)} old alerts"
    )

    %{state | alerts: new_alerts}
  end

  defp cleanup_ets_tables do
    # Clean up any large ETS tables
    [:schema_cache, :variable_spaces, :variable_configs]
    |> Enum.each(fn table_name ->
      if :ets.whereis(table_name) != :undefined do
        size = :ets.info(table_name, :size)

        if size > 1000 do
          # Delete oldest entries if table is too large
          Logger.info("Cleaning up ETS table #{table_name} with #{size} entries")
        end
      end
    end)
  end

  defp get_erlang_memory_stats do
    memory_info = :erlang.memory()

    %{
      total: Keyword.get(memory_info, :total, 0),
      processes: Keyword.get(memory_info, :processes, 0),
      system: Keyword.get(memory_info, :system, 0),
      atom: Keyword.get(memory_info, :atom, 0),
      binary: Keyword.get(memory_info, :binary, 0),
      ets: Keyword.get(memory_info, :ets, 0)
    }
  end

  defp check_resource_alerts(state, current_memory_mb) do
    alerts = []

    # Memory usage alerts
    # 80% threshold
    memory_threshold = state.max_memory_mb * 0.8

    alerts =
      if current_memory_mb > memory_threshold do
        alert = %{
          type: :high_memory_usage,
          severity: :warning,
          message:
            "Memory usage is #{Float.round(current_memory_mb, 2)}MB (#{Float.round(current_memory_mb / state.max_memory_mb * 100, 1)}%)",
          timestamp: System.monotonic_time(:millisecond)
        }

        [alert | alerts]
      else
        alerts
      end

    # Process count alerts
    # 80% threshold
    process_threshold = state.max_processes * 0.8

    alerts =
      if state.current_process_count > process_threshold do
        alert = %{
          type: :high_process_count,
          severity: :warning,
          message:
            "Process count is #{state.current_process_count} (#{Float.round(state.current_process_count / state.max_processes * 100, 1)}%)",
          timestamp: System.monotonic_time(:millisecond)
        }

        [alert | alerts]
      else
        alerts
      end

    # Log new alerts
    new_alerts = alerts -- state.alerts

    Enum.each(new_alerts, fn alert ->
      Logger.warning("Resource alert: #{alert.message}")
    end)

    alerts ++ state.alerts
  end
end
