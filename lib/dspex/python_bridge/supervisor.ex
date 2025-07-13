defmodule DSPex.PythonBridge.Supervisor do
  @moduledoc """
  Supervisor for Python bridge components.

  This supervisor manages the lifecycle of the Python bridge system, including
  the main bridge GenServer and health monitoring components. It provides
  fault tolerance and automatic restart capabilities.

  ## Supervision Strategy

  Uses a `:one_for_one` strategy with the following components:
  - **Bridge**: The main Python communication GenServer
  - **Monitor**: Health monitoring and metrics collection

  ## Restart Strategy

  - **Bridge**: `:permanent` - Always restart if it terminates
  - **Monitor**: `:permanent` - Always restart if it terminates
  - **Max Restarts**: 5 restarts within 60 seconds before giving up

  ## Architecture

  ```
  DSPex.PythonBridge.Supervisor
  ├── DSPex.PythonBridge.Bridge (permanent)
  └── DSPex.PythonBridge.Monitor (permanent)
  ```

  ## Usage

      # Start the bridge supervisor
      {:ok, pid} = DSPex.PythonBridge.Supervisor.start_link()

      # Get supervisor status
      children = DSPex.PythonBridge.Supervisor.which_children()

      # Stop the supervisor
      :ok = DSPex.PythonBridge.Supervisor.stop()

  ## Configuration

      config :dspex, :python_bridge_supervisor,
        max_restarts: 5,
        max_seconds: 60,
        bridge_restart: :permanent,
        monitor_restart: :permanent
  """

  use Supervisor
  require Logger

  @default_config %{
    max_restarts: 5,
    max_seconds: 60,
    bridge_restart: :permanent,
    monitor_restart: :permanent
  }

  ## Public API

  @doc """
  Starts the Python bridge supervisor.

  Initializes and starts all bridge components under supervision.

  ## Options

  - `:name` - The name to register the supervisor (default: `__MODULE__`)
  - `:max_restarts` - Maximum number of restarts within max_seconds
  - `:max_seconds` - Time window for restart counting
  - `:bridge_restart` - Restart strategy for bridge (:permanent, :temporary, :transient)
  - `:monitor_restart` - Restart strategy for monitor (:permanent, :temporary, :transient)

  ## Examples

      {:ok, pid} = DSPex.PythonBridge.Supervisor.start_link()
      {:ok, pid} = DSPex.PythonBridge.Supervisor.start_link(name: MyBridgeSupervisor)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns information about all supervised children.

  ## Examples

      children = DSPex.PythonBridge.Supervisor.which_children()
      # => [
      #   {DSPex.PythonBridge.Bridge, #PID<0.123.0>, :worker, [DSPex.PythonBridge.Bridge]},
      #   {DSPex.PythonBridge.Monitor, #PID<0.124.0>, :worker, [DSPex.PythonBridge.Monitor]}
      # ]
  """
  @spec which_children() :: [{any(), pid() | :undefined, :worker | :supervisor, [module()]}]
  def which_children do
    Supervisor.which_children(__MODULE__)
  end

  @doc """
  Returns the count and status of supervised children.

  ## Examples

      count = DSPex.PythonBridge.Supervisor.count_children()
      # => %{active: 2, specs: 2, supervisors: 0, workers: 2}
  """
  @spec count_children() :: %{
          specs: non_neg_integer(),
          active: non_neg_integer(),
          supervisors: non_neg_integer(),
          workers: non_neg_integer()
        }
  def count_children do
    Supervisor.count_children(__MODULE__)
  end

  @doc """
  Terminates a specific child process.

  The child will be restarted according to its restart strategy.

  ## Examples

      :ok = DSPex.PythonBridge.Supervisor.terminate_child(DSPex.PythonBridge.Bridge)
  """
  @spec terminate_child(module()) :: :ok | {:error, :not_found}
  def terminate_child(child_module) do
    Supervisor.terminate_child(__MODULE__, child_module)
  end

  @doc """
  Restarts a specific child process.

  ## Examples

      {:ok, pid} = DSPex.PythonBridge.Supervisor.restart_child(DSPex.PythonBridge.Bridge)
  """
  @spec restart_child(module()) ::
          {:ok, pid()}
          | {:ok, pid(), any()}
          | {:error, :not_found | :running | :restarting | any()}
  def restart_child(child_module) do
    Supervisor.restart_child(__MODULE__, child_module)
  end

  @doc """
  Stops the supervisor gracefully.

  This will terminate all supervised children before stopping the supervisor.

  ## Examples

      :ok = DSPex.PythonBridge.Supervisor.stop()
  """
  @spec stop() :: :ok
  def stop do
    Supervisor.stop(__MODULE__)
  end

  @doc """
  Stops a specific supervisor process by PID.

  ## Examples

      :ok = DSPex.PythonBridge.Supervisor.stop(pid)
  """
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal, 5000)
  end

  @doc """
  Stops a specific supervisor process by PID with custom reason and timeout.

  ## Examples

      :ok = DSPex.PythonBridge.Supervisor.stop(pid, :shutdown, 1000)
  """
  @spec stop(pid(), term(), timeout()) :: :ok
  def stop(pid, reason, timeout) when is_pid(pid) do
    GenServer.stop(pid, reason, timeout)
  end

  @doc """
  Gets the health status of all bridge components.

  Returns aggregated health information from all supervised processes.

  ## Examples

      status = DSPex.PythonBridge.Supervisor.get_system_status()
      # => %{
      #   supervisor: :running,
      #   bridge: %{status: :running, ...},
      #   monitor: %{status: :healthy, ...}
      # }
  """
  @spec get_system_status() :: %{
          bridge: map(),
          children_count: non_neg_integer(),
          last_check: DateTime.t(),
          monitor: map(),
          supervisor: :running
        }
  def get_system_status do
    children = which_children()

    bridge_status = get_child_status(DSPex.PythonBridge.Bridge)
    monitor_status = get_child_status(DSPex.PythonBridge.Monitor)

    %{
      supervisor: :running,
      children_count: length(children),
      bridge: bridge_status,
      monitor: monitor_status,
      last_check: DateTime.utc_now()
    }
  end

  ## Supervisor Callbacks

  @impl true
  def init(opts) do
    config = build_config(opts)

    # Support dynamic child names for test isolation
    bridge_name = Keyword.get(opts, :bridge_name, DSPex.PythonBridge.Bridge)
    monitor_name = Keyword.get(opts, :monitor_name, DSPex.PythonBridge.Monitor)

    Logger.info("Starting Python bridge supervisor with config: #{inspect(config)}")

    children = [
      # Start bridge first
      {DSPex.PythonBridge.Bridge, [restart: config.bridge_restart, name: bridge_name]},

      # Start monitor after bridge  
      {DSPex.PythonBridge.Monitor,
       [restart: config.monitor_restart, name: monitor_name, bridge_name: bridge_name]}
    ]

    supervisor_opts = [
      strategy: :one_for_one,
      max_restarts: config.max_restarts,
      max_seconds: config.max_seconds
    ]

    Supervisor.init(children, supervisor_opts)
  end

  ## Private Functions

  defp build_config(opts) do
    app_config = Application.get_env(:dspex, :python_bridge_supervisor, %{})

    @default_config
    |> Map.merge(Map.new(app_config))
    |> Map.merge(Map.new(opts))
  end

  defp get_child_status(child_module) do
    try do
      case child_module do
        DSPex.PythonBridge.Bridge ->
          DSPex.PythonBridge.Bridge.get_status()

        DSPex.PythonBridge.Monitor ->
          DSPex.PythonBridge.Monitor.get_health_status()
      end
    catch
      :exit, {:noproc, _} -> %{status: :not_running}
      :exit, {:timeout, _} -> %{status: :timeout}
      error -> %{status: :error, error: inspect(error)}
    end
  end

  @doc """
  Performs a graceful shutdown of all bridge components.

  This function ensures that:
  1. New requests are rejected
  2. Existing requests are completed or timed out
  3. Python processes are cleanly terminated
  4. Resources are properly cleaned up

  ## Examples

      :ok = DSPex.PythonBridge.Supervisor.graceful_shutdown()
      :ok = DSPex.PythonBridge.Supervisor.graceful_shutdown(timeout: 10_000)
  """
  @spec graceful_shutdown(keyword()) :: :ok
  def graceful_shutdown(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    Logger.info("Initiating graceful shutdown of Python bridge system")

    # Stop accepting new requests by terminating monitor first
    case terminate_child(DSPex.PythonBridge.Monitor) do
      :ok -> Logger.info("Monitor terminated successfully")
      {:error, reason} -> Logger.warning("Failed to terminate monitor: #{inspect(reason)}")
    end

    # Wait for bridge to complete pending requests
    case wait_for_bridge_idle() do
      :ok -> Logger.debug("Bridge completed pending requests")
      {:error, reason} -> Logger.warning("Bridge idle wait failed: #{inspect(reason)}")
    end

    # Terminate bridge
    case terminate_child(DSPex.PythonBridge.Bridge) do
      :ok -> Logger.info("Bridge terminated successfully")
      {:error, reason} -> Logger.warning("Failed to terminate bridge: #{inspect(reason)}")
    end

    # Wait for clean termination
    wait_for_termination(timeout)

    Logger.info("Python bridge graceful shutdown completed")
    :ok
  end

  defp wait_for_termination(timeout) do
    start_time = System.monotonic_time(:millisecond)
    wait_for_termination_loop(start_time, timeout)
  end

  defp wait_for_termination_loop(start_time, timeout) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time
    remaining_timeout = max(0, timeout - elapsed)

    if remaining_timeout <= 0 do
      Logger.warning("Graceful shutdown timeout reached")
      :timeout
    else
      case count_children() do
        %{active: 0} ->
          :ok

        _children_status ->
          # Wait for child termination event instead of polling
          receive do
            {:EXIT, _pid, _reason} ->
              wait_for_termination_loop(start_time, timeout)
          after
            min(remaining_timeout, 100) ->
              wait_for_termination_loop(start_time, timeout)
          end
      end
    end
  end

  @doc """
  Performs a health check on the entire bridge system.

  Verifies that all components are running and responding properly.

  ## Examples

      case DSPex.PythonBridge.Supervisor.system_health_check() do
        :ok -> Logger.info("System healthy")
        {:error, issues} -> Logger.error("System issues: \#{inspect(issues)}")
      end
  """
  @spec system_health_check() :: :ok | {:error, [String.t()]}
  def system_health_check do
    issues = []

    # Check if supervisor is running
    issues = check_supervisor_health(issues)

    # Check bridge status
    issues = check_bridge_health(issues)

    # Check monitor status
    issues = check_monitor_health(issues)

    case issues do
      [] -> :ok
      problems -> {:error, problems}
    end
  end

  defp check_supervisor_health(issues) do
    case count_children() do
      %{active: count} when count > 0 -> issues
      _ -> ["Supervisor has no active children" | issues]
    end
  end

  defp check_bridge_health(issues) do
    case get_child_status(DSPex.PythonBridge.Bridge) do
      %{status: :running} -> issues
      %{status: status} -> ["Bridge not running: #{status}" | issues]
    end
  end

  defp check_monitor_health(issues) do
    case get_child_status(DSPex.PythonBridge.Monitor) do
      %{status: status} when status in [:healthy, :degraded] -> issues
      %{status: status} -> ["Monitor unhealthy: #{status}" | issues]
    end
  end

  defp wait_for_bridge_idle(timeout \\ 3000) do
    start_time = System.monotonic_time(:millisecond)
    wait_for_bridge_idle_loop(start_time, timeout)
  end

  defp wait_for_bridge_idle_loop(start_time, timeout) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time

    if elapsed >= timeout do
      {:error, :timeout}
    else
      case get_child_status(DSPex.PythonBridge.Bridge) do
        %{stats: %{pending_requests: 0}} ->
          :ok

        %{stats: %{pending_requests: count}} when count > 0 ->
          # Bridge has pending requests, wait a bit
          remaining_timeout = timeout - elapsed
          wait_time = min(remaining_timeout, 50)

          receive do
          after
            wait_time ->
              wait_for_bridge_idle_loop(start_time, timeout)
          end

        _ ->
          # Bridge not available or no stats, consider it idle
          :ok
      end
    end
  end
end
