defmodule DSPex.UnifiedTestFoundation do
  @moduledoc """
  Unified test foundation implementing isolation patterns from UNIFIED_TESTING_GUIDE.md

  Provides different isolation modes for different types of tests:
  - :basic - Minimal isolation for simple tests
  - :registry - Isolated registry for agent/process tests  
  - :signal_routing - Isolated signal bus for event tests
  - :full_isolation - Complete service isolation
  - :contamination_detection - Full isolation + contamination monitoring
  - :supervision_testing - Isolated supervision trees for crash recovery tests
  - :pool_testing - Isolated pools with supervision tree and performance monitoring

  Each mode provides appropriate setup and teardown for test independence.
  """

  require Logger
  import ExUnit.Callbacks, only: [on_exit: 1]
  import DSPex.SupervisionTestHelpers, only: [graceful_supervisor_shutdown: 2, wait_for: 2]

  @doc """
  Macro for using the unified test foundation with a specific isolation mode.

  This sets up the appropriate test configuration, imports helper functions,
  and configures ExUnit settings based on the isolation requirements.
  """
  defmacro __using__(isolation_type) do
    quote do
      use ExUnit.Case, async: unquote(__MODULE__).isolation_allows_async?(unquote(isolation_type))
      import DSPex.SupervisionTestHelpers
      import DSPex.BridgeTestHelpers
      import DSPex.MonitorTestHelpers

      # Set appropriate timeouts based on isolation type
      @moduletag timeout: unquote(__MODULE__).isolation_timeout(unquote(isolation_type))

      # Tag tests with their isolation type for filtering
      @moduletag isolation: unquote(isolation_type)

      setup context do
        unquote(__MODULE__).setup_isolation(unquote(isolation_type), context)
      end
    end
  end

  @doc """
  Determines if an isolation type allows async test execution.

  Some isolation types require sequential execution to prevent interference.
  """
  @spec isolation_allows_async?(atom()) :: boolean()
  def isolation_allows_async?(:supervision_testing), do: false
  def isolation_allows_async?(:contamination_detection), do: false
  def isolation_allows_async?(:full_isolation), do: false
  def isolation_allows_async?(:pool_testing), do: false
  def isolation_allows_async?(_), do: true

  @doc """
  Returns appropriate timeout for isolation type.

  More complex isolation setups need longer timeouts.
  """
  @spec isolation_timeout(atom()) :: pos_integer()
  def isolation_timeout(:supervision_testing), do: 30_000
  def isolation_timeout(:contamination_detection), do: 60_000
  def isolation_timeout(:full_isolation), do: 20_000
  def isolation_timeout(:pool_testing), do: 60_000
  def isolation_timeout(_), do: 10_000

  @doc """
  Sets up isolation for a specific test based on the isolation type.

  Returns a context map with the necessary resources and cleanup functions.
  """
  @spec setup_isolation(atom(), map()) :: {:ok, map()}
  def setup_isolation(isolation_type, context) do
    case isolation_type do
      :basic -> setup_basic_isolation(context)
      :registry -> setup_registry_isolation(context)
      :signal_routing -> setup_signal_routing_isolation(context)
      :full_isolation -> setup_full_isolation(context)
      :contamination_detection -> setup_contamination_detection(context)
      :supervision_testing -> setup_supervision_testing(context)
      :pool_testing -> setup_pool_testing(context)
      _ -> {:error, {:unknown_isolation_type, isolation_type}}
    end
  end

  ## Isolation Mode Implementations

  defp setup_basic_isolation(context) do
    unique_id = :erlang.unique_integer([:positive])

    test_context =
      Map.merge(context, %{
        test_id: unique_id,
        isolation_type: :basic
      })

    {:ok, test_context}
  end

  defp setup_registry_isolation(context) do
    unique_id = :erlang.unique_integer([:positive])
    registry_name = :"test_registry_#{unique_id}"

    # Start isolated registry
    {:ok, registry_pid} = Registry.start_link(keys: :unique, name: registry_name)

    # Setup cleanup
    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid, :normal, 1000)
      end
    end)

    test_context =
      Map.merge(context, %{
        test_id: unique_id,
        registry: registry_name,
        registry_pid: registry_pid,
        isolation_type: :registry
      })

    {:ok, test_context}
  end

  defp setup_signal_routing_isolation(context) do
    unique_id = :erlang.unique_integer([:positive])

    # For signal routing, we'd typically set up an isolated event bus
    # This is a placeholder for the actual signal routing system
    signal_bus_name = :"test_signal_bus_#{unique_id}"

    test_context =
      Map.merge(context, %{
        test_id: unique_id,
        signal_bus: signal_bus_name,
        isolation_type: :signal_routing
      })

    {:ok, test_context}
  end

  defp setup_full_isolation(context) do
    unique_id = :erlang.unique_integer([:positive])

    # Set up complete service isolation
    registry_name = :"test_registry_#{unique_id}"
    supervisor_name = :"test_supervisor_#{unique_id}"

    # Start isolated registry
    {:ok, registry_pid} = Registry.start_link(keys: :unique, name: registry_name)

    # Setup cleanup
    on_exit(fn ->
      cleanup_full_isolation(registry_pid)
    end)

    test_context =
      Map.merge(context, %{
        test_id: unique_id,
        registry: registry_name,
        registry_pid: registry_pid,
        supervisor_name: supervisor_name,
        isolation_type: :full_isolation
      })

    {:ok, test_context}
  end

  defp setup_contamination_detection(context) do
    _unique_id = :erlang.unique_integer([:positive])

    # Set up full isolation plus contamination monitoring
    {:ok, full_context} = setup_full_isolation(context)

    # Add contamination monitoring
    contamination_monitor = spawn_link(fn -> contamination_monitor_loop([]) end)

    # Enhanced cleanup with contamination check
    on_exit(fn ->
      send(contamination_monitor, {:check_contamination, self()})

      receive do
        {:contamination_result, contaminations} ->
          unless Enum.empty?(contaminations) do
            Logger.warning("Test contamination detected: #{inspect(contaminations)}")
          end
      after
        1000 -> :ok
      end

      cleanup_full_isolation(full_context.registry_pid)
    end)

    test_context =
      Map.merge(full_context, %{
        contamination_monitor: contamination_monitor,
        isolation_type: :contamination_detection
      })

    {:ok, test_context}
  end

  defp setup_supervision_testing(context) do
    unique_id = :erlang.unique_integer([:positive])

    # Create unique names for all components
    supervisor_name = :"test_supervisor_#{unique_id}"
    bridge_name = :"test_bridge_#{unique_id}"
    monitor_name = :"test_monitor_#{unique_id}"

    # Start isolated supervision tree
    case start_isolated_supervisor(supervisor_name, bridge_name, monitor_name) do
      {:ok, supervisor_pid} ->
        # Setup cleanup
        on_exit(fn ->
          graceful_supervisor_shutdown(supervisor_pid, 10_000)
        end)

        test_context =
          Map.merge(context, %{
            test_id: unique_id,
            supervision_tree: supervisor_pid,
            supervisor_name: supervisor_name,
            bridge_name: bridge_name,
            monitor_name: monitor_name,
            isolation_type: :supervision_testing
          })

        {:ok, test_context}

      {:error, reason} ->
        Logger.error("Failed to start isolated supervisor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp setup_pool_testing(context) do
    unique_id = :erlang.unique_integer([:positive])

    # Create unique names for all pool components
    pool_name = :"test_pool_#{unique_id}"
    supervisor_name = :"test_supervisor_#{unique_id}"
    bridge_name = :"test_bridge_#{unique_id}"
    monitor_name = :"test_monitor_#{unique_id}"
    registry_name = :"test_registry_#{unique_id}"

    # Start isolated registry for pool components
    {:ok, registry_pid} = Registry.start_link(keys: :unique, name: registry_name)

    # Start isolated supervision tree
    case start_isolated_supervisor(supervisor_name, bridge_name, monitor_name) do
      {:ok, supervisor_pid} ->
        # Wait for supervision tree to be ready
        case wait_for_supervision_tree_ready(supervisor_pid, 30_000) do
          result when result in [{:ok, :ready}, :ok] ->
            # Start isolated pool using the SessionPoolV2
            pool_config = [
              pool_size: 4,
              overflow: 2,
              name: pool_name,
              worker_module: DSPex.PythonBridge.PoolWorkerV2Enhanced
            ]

            pool_result =
              ExUnit.Callbacks.start_supervised({DSPex.PythonBridge.SessionPoolV2, pool_config})

            pool_pid =
              case pool_result do
                {:ok, pid} -> pid
                pid when is_pid(pid) -> pid
                error -> error
              end

            case pool_pid do
              pid when is_pid(pid) ->
                # Get actual pool name for operations
                actual_pool_name = DSPex.PythonBridge.SessionPoolV2.get_pool_name_for(pool_name)

                # Setup cleanup
                on_exit(fn ->
                  cleanup_pool_testing(pid, supervisor_pid, registry_pid)
                end)

                test_context =
                  Map.merge(context, %{
                    test_id: unique_id,
                    pool_pid: pid,
                    pool_name: pool_name,
                    actual_pool_name: actual_pool_name,
                    supervision_tree: supervisor_pid,
                    supervisor_name: supervisor_name,
                    bridge_name: bridge_name,
                    monitor_name: monitor_name,
                    registry: registry_name,
                    registry_pid: registry_pid,
                    isolation_type: :pool_testing,
                    pool_config: pool_config
                  })

                {:ok, test_context}

              error ->
                graceful_supervisor_shutdown(supervisor_pid, 10_000)
                cleanup_full_isolation(registry_pid)
                Logger.error("Failed to start isolated pool: #{inspect(error)}")
                {:error, error}
            end

          {:error, reason} ->
            graceful_supervisor_shutdown(supervisor_pid, 10_000)
            cleanup_full_isolation(registry_pid)
            Logger.error("Supervision tree not ready: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        cleanup_full_isolation(registry_pid)
        Logger.error("Failed to start isolated supervisor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  ## Helper Functions

  defp start_isolated_supervisor(supervisor_name, bridge_name, monitor_name) do
    supervisor_opts = [
      name: supervisor_name,
      bridge_name: bridge_name,
      monitor_name: monitor_name
    ]

    case DSPex.PythonBridge.Supervisor.start_link(supervisor_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp cleanup_full_isolation(registry_pid) do
    if Process.alive?(registry_pid) do
      # Get all registered processes
      registered_processes = Registry.select(registry_pid, [{{:"$1", :"$2", :"$3"}, [], [:"$2"]}])

      # Terminate all registered processes
      Enum.each(registered_processes, fn pid ->
        if Process.alive?(pid) do
          Process.exit(pid, :kill)
        end
      end)

      # Stop the registry
      GenServer.stop(registry_pid, :normal, 1000)
    end
  end

  defp cleanup_pool_testing(pool_pid, supervisor_pid, registry_pid) do
    # Stop pool first
    if Process.alive?(pool_pid) do
      try do
        GenServer.stop(pool_pid, :normal, 5000)
      catch
        :exit, _ -> :ok
      end
    end

    # Then cleanup supervision tree and registry
    graceful_supervisor_shutdown(supervisor_pid, 10_000)
    cleanup_full_isolation(registry_pid)
  end

  defp contamination_monitor_loop(contaminations) do
    receive do
      {:process_started, {name, pid}} ->
        contamination_monitor_loop([{:process_started, name, pid} | contaminations])

      {:process_terminated, {name, pid}} ->
        contamination_monitor_loop([{:process_terminated, name, pid} | contaminations])

      {:check_contamination, caller} ->
        send(caller, {:contamination_result, contaminations})
        contamination_monitor_loop([])

      _ ->
        contamination_monitor_loop(contaminations)
    end
  end

  @doc """
  Waits for all processes in a supervision tree to be ready.

  This is used after starting an isolated supervision tree to ensure
  all children are fully initialized before tests proceed.
  """
  @spec wait_for_supervision_tree_ready(pid(), timeout()) :: :ok | {:error, term()}
  def wait_for_supervision_tree_ready(supervisor_pid, timeout \\ 10_000) do
    wait_for(
      fn ->
        case get_supervision_tree_status(supervisor_pid) do
          {:ok, :all_running} ->
            {:ok, :ready}

          {:ok, status} ->
            Logger.debug("Supervision tree status: #{status}")
            nil

          {:error, reason} ->
            Logger.debug("Supervision tree check failed: #{inspect(reason)}")
            nil
        end
      end,
      timeout
    )
  end

  defp get_supervision_tree_status(supervisor_pid) do
    try do
      case Supervisor.which_children(supervisor_pid) do
        children when is_list(children) ->
          statuses =
            Enum.map(children, fn {name, pid, _type, _modules} ->
              {name, if(is_pid(pid), do: :running, else: :not_running)}
            end)

          if Enum.all?(statuses, fn {_name, status} -> status == :running end) do
            {:ok, :all_running}
          else
            {:ok, {:partial, statuses}}
          end

        error ->
          {:error, {:supervisor_error, error}}
      end
    catch
      :exit, reason -> {:error, {:supervisor_exit, reason}}
      error -> {:error, error}
    end
  end

  @doc """
  Creates a test-specific configuration for bridge components.

  This ensures each test gets unique process names and configurations
  to prevent conflicts in parallel execution.
  """
  @spec create_test_bridge_config(integer()) :: map()
  def create_test_bridge_config(unique_id) do
    %{
      bridge_name: :"test_bridge_#{unique_id}",
      monitor_name: :"test_monitor_#{unique_id}",
      supervisor_name: :"test_supervisor_#{unique_id}",
      python_executable: System.get_env("PYTHON_EXECUTABLE", "python3"),
      python_timeout: 5000,
      # Faster for testing
      health_check_interval: 500,
      failure_threshold: 2,
      max_restart_attempts: 3
    }
  end

  @doc """
  Verifies test isolation by checking for process leaks.

  This can be called at the end of tests to ensure no processes
  were left running that could affect subsequent tests.
  """
  @spec verify_test_isolation(map()) :: :ok | {:error, term()}
  def verify_test_isolation(%{test_id: test_id}) do
    # Check for any processes with our test ID in their name
    all_processes = Process.list()

    test_processes =
      Enum.filter(all_processes, fn pid ->
        case Process.info(pid, :registered_name) do
          {:registered_name, name} when is_atom(name) ->
            String.contains?(Atom.to_string(name), "#{test_id}")

          _ ->
            false
        end
      end)

    if Enum.empty?(test_processes) do
      :ok
    else
      {:error, {:process_leak, test_processes}}
    end
  end

  # Private helper imported by all isolation modes - removed due to import conflict
end
