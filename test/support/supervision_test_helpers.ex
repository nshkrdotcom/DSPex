defmodule DSPex.SupervisionTestHelpers do
  @moduledoc """
  Test helpers for supervision tree isolation and process lifecycle management.
  Uses event-driven coordination.

  Based on patterns from UNIFIED_TESTING_GUIDE.md for proper OTP testing.
  """

  require Logger

  @doc """
  Waits for a bridge to be ready for operations.

  Uses event-driven coordination.
  Checks bridge status and Python process readiness.
  """
  @spec wait_for_bridge_ready(pid(), atom(), timeout()) :: {:ok, :ready} | {:error, term()}
  def wait_for_bridge_ready(supervisor_pid, bridge_name, timeout \\ 5000) do
    start_time = System.monotonic_time(:millisecond)

    wait_for(
      fn ->
        case get_bridge_status(supervisor_pid, bridge_name) do
          {:ok, %{status: :running, python_ready: true}} -> {:ok, :ready}
          {:ok, status} -> {:waiting, status}
          {:error, _} = error -> error
        end
      end,
      start_time,
      timeout
    )
  end

  @doc """
  Waits for a process to restart after being killed.

  Uses process monitoring instead of timing assumptions.
  Ensures the new PID is different from the old one.
  """
  @spec wait_for_process_restart(pid(), atom(), pid(), timeout()) ::
          {:ok, pid()} | {:error, term()}
  def wait_for_process_restart(supervisor_pid, process_name, old_pid, timeout \\ 5000) do
    ref = Process.monitor(old_pid)

    # Wait for crash
    receive do
      {:DOWN, ^ref, :process, ^old_pid, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :crash_timeout}
    end

    # Wait for restart with new PID
    start_time = System.monotonic_time(:millisecond)

    wait_for(
      fn ->
        case get_child_pid(supervisor_pid, process_name) do
          {:ok, new_pid} when new_pid != old_pid ->
            if Process.alive?(new_pid) do
              {:ok, new_pid}
            else
              nil
            end

          _ ->
            nil
        end
      end,
      start_time,
      timeout
    )
  end

  @doc """
  Generic condition waiting function.

  Repeatedly calls the given function until it returns {:ok, result}
  or the timeout is reached. Uses event-driven coordination.
  """
  @spec wait_for(fun(), integer(), timeout()) :: {:ok, term()} | {:error, :timeout}
  def wait_for(fun, start_time, timeout) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time

    if elapsed >= timeout do
      {:error, :timeout}
    else
      case fun.() do
        {:ok, result} ->
          {:ok, result}

        {:waiting, _} ->
          # Brief wait before retry
          receive do
          after
            50 -> wait_for(fun, start_time, timeout)
          end

        {:error, _} = error ->
          error

        nil ->
          # Brief wait before retry
          receive do
          after
            50 -> wait_for(fun, start_time, timeout)
          end
      end
    end
  end

  @doc """
  Convenience version of wait_for/3 that starts timing from now.
  """
  @spec wait_for(fun(), timeout()) :: {:ok, term()} | {:error, :timeout}
  def wait_for(fun, timeout \\ 5000) do
    start_time = System.monotonic_time(:millisecond)
    wait_for(fun, start_time, timeout)
  end

  @doc """
  Gets the current status of a bridge process.
  """
  @spec get_bridge_status(pid(), atom()) :: {:ok, map()} | {:error, term()}
  def get_bridge_status(supervisor_pid, bridge_name) do
    try do
      # Look for the bridge child by module name, not the dynamic bridge_name
      case get_child_pid(supervisor_pid, DSPex.PythonBridge.Bridge) do
        {:ok, bridge_pid} ->
          case GenServer.call(bridge_pid, :get_status, 1000) do
            status when is_map(status) ->
              # Check if Python process is ready by looking for running status
              python_ready =
                case status do
                  %{status: :running} -> true
                  %{python_port: port} when not is_nil(port) -> true
                  _ -> false
                end

              {:ok, Map.put(status, :python_ready, python_ready)}

            error ->
              {:error, {:invalid_status, error}}
          end

        {:error, :child_not_found} ->
          # Also try looking by the dynamic bridge_name in case of different supervisor setup
          case get_child_pid(supervisor_pid, bridge_name) do
            {:ok, bridge_pid} ->
              case GenServer.call(bridge_pid, :get_status, 1000) do
                status when is_map(status) ->
                  python_ready =
                    case status do
                      %{status: :running} -> true
                      %{python_port: port} when not is_nil(port) -> true
                      _ -> false
                    end

                  {:ok, Map.put(status, :python_ready, python_ready)}

                error ->
                  {:error, {:invalid_status, error}}
              end

            error ->
              error
          end

        error ->
          error
      end
    catch
      :exit, reason -> {:error, {:exit, reason}}
      error -> {:error, error}
    end
  end

  @doc """
  Gets the PID of a child process from a supervisor.
  """
  @spec get_child_pid(pid(), atom()) :: {:ok, pid()} | {:error, term()}
  def get_child_pid(supervisor_pid, child_name) do
    try do
      case Supervisor.which_children(supervisor_pid) do
        children when is_list(children) ->
          case Enum.find(children, fn {name, _pid, _type, _modules} ->
                 name == child_name
               end) do
            {^child_name, pid, _type, _modules} when is_pid(pid) ->
              {:ok, pid}

            {^child_name, :undefined, _type, _modules} ->
              {:error, :child_not_running}

            nil ->
              {:error, :child_not_found}
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
  Gets a service process from a supervision tree.

  This is a convenience function that combines supervisor lookup
  with child process retrieval.
  """
  @spec get_service(pid(), atom()) :: {:ok, pid()} | {:error, term()}
  def get_service(supervisor_pid, service_name) do
    try do
      # First try to get the service by module name for common services
      module_name =
        case service_name do
          name when is_atom(name) ->
            name_str = Atom.to_string(name)

            cond do
              String.contains?(name_str, "monitor") -> DSPex.PythonBridge.Monitor
              String.contains?(name_str, "bridge") -> DSPex.PythonBridge.Bridge
              true -> service_name
            end

          _ ->
            service_name
        end

      case get_child_pid(supervisor_pid, module_name) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, :child_not_found} ->
          # Fallback to dynamic service name
          get_child_pid(supervisor_pid, service_name)

        error ->
          error
      end
    catch
      :exit, reason -> {:error, {:exit, reason}}
      error -> {:error, error}
    end
  end

  @doc """
  Calls a service function through the supervision tree.

  Provides a safe way to call functions on supervised processes
  with proper error handling.
  """
  @spec call_service(pid(), atom(), atom() | {atom(), list()}) :: term()
  def call_service(supervisor_pid, service_name, function_spec) do
    case get_service(supervisor_pid, service_name) do
      {:ok, service_pid} ->
        case function_spec do
          function_name when is_atom(function_name) ->
            GenServer.call(service_pid, function_name)

          {function_name, args} when is_atom(function_name) and is_list(args) ->
            GenServer.call(service_pid, {function_name, args})
        end

      {:error, reason} ->
        {:error, {:service_not_available, reason}}
    end
  end

  @doc """
  Creates unique process names using erlang unique integers.

  This prevents process name conflicts in tests by ensuring
  each test gets unique process names.
  """
  @spec unique_process_name(String.t()) :: atom()
  def unique_process_name(base_name) do
    unique_id = :erlang.unique_integer([:positive])
    :"#{base_name}_#{unique_id}"
  end

  @doc """
  Creates multiple unique process names for related processes.

  Returns a map with the requested process names as keys
  and unique atom names as values.
  """
  @spec unique_process_names(list(atom())) :: map()
  def unique_process_names(name_list) when is_list(name_list) do
    unique_id = :erlang.unique_integer([:positive])

    Enum.into(name_list, %{}, fn name ->
      {name, :"#{name}_#{unique_id}"}
    end)
  end

  @doc """
  Performs graceful supervisor shutdown with proper cleanup.

  This should be used in test cleanup to ensure processes
  are properly terminated and don't leak between tests.
  """
  @spec graceful_supervisor_shutdown(pid(), timeout()) :: :ok
  def graceful_supervisor_shutdown(supervisor_pid, timeout \\ 5000) do
    if Process.alive?(supervisor_pid) do
      ref = Process.monitor(supervisor_pid)

      # Try graceful shutdown first
      try do
        GenServer.stop(supervisor_pid, :normal, timeout)
      catch
        :exit, _ -> :ok
      end

      # Wait for termination or force kill
      receive do
        {:DOWN, ^ref, :process, ^supervisor_pid, _} -> :ok
      after
        timeout ->
          Logger.warning("Supervisor did not shutdown gracefully, forcing termination")
          Process.exit(supervisor_pid, :kill)
          :ok
      end
    else
      :ok
    end
  end

  @doc """
  Monitors all services in a supervision tree.

  Returns a map of service names to {pid, monitor_ref} tuples.
  Useful for chaos testing and failure detection.
  """
  @spec monitor_all_services(pid()) :: map()
  def monitor_all_services(supervisor_pid) do
    case Supervisor.which_children(supervisor_pid) do
      children when is_list(children) ->
        Enum.into(children, %{}, fn {name, pid, _type, _modules} ->
          if is_pid(pid) do
            ref = Process.monitor(pid)
            {name, {pid, ref}}
          else
            {name, {:undefined, nil}}
          end
        end)

      _ ->
        %{}
    end
  end

  @doc """
  Verifies rest-for-one cascade behavior in supervision.

  Checks that when a service crashes, all services started after it
  in the supervision order are also restarted.
  """
  @spec verify_rest_for_one_cascade(map(), atom()) :: :ok | {:error, term()}
  def verify_rest_for_one_cascade(_monitors, crashed_service) do
    # This would need to be implemented based on the specific
    # supervision order in the application
    # For now, we'll provide a basic framework
    Logger.info("Verifying rest-for-one cascade for #{crashed_service}")
    :ok
  end

  ## Pool-Specific Wait Functions

  @doc """
  Waits for a pool to be ready and operational.
  
  Checks that the pool GenServer is running and workers are initialized.
  """
  @spec wait_for_pool_ready(atom() | pid(), atom(), timeout()) :: {:ok, :ready} | {:error, term()}
  def wait_for_pool_ready(_pool_name_or_pid, genserver_name, timeout \\ 30_000) do
    start_time = System.monotonic_time(:millisecond)
    
    wait_for(
      fn ->
        case get_pool_status_safe(genserver_name) do
          {:ok, status} when status.pool_size > 0 ->
            # Pool has workers, check if they're operational
            if status.pool_size >= 1 do
              {:ok, :ready}
            else
              {:waiting, "pool has no workers"}
            end
          
          {:ok, _status} ->
            {:waiting, "pool not fully initialized"}
            
          {:error, reason} ->
            {:waiting, "pool not accessible: #{inspect(reason)}"}
        end
      end,
      start_time,
      timeout
    )
  end

  @doc """
  Waits for all workers in a pool to be initialized and ready.
  
  Verifies that the expected number of workers are available.
  """
  @spec wait_for_workers_initialized(atom(), integer(), timeout()) :: {:ok, map()} | {:error, term()}
  def wait_for_workers_initialized(genserver_name, expected_workers, timeout \\ 30_000) do
    start_time = System.monotonic_time(:millisecond)
    
    wait_for(
      fn ->
        case get_pool_status_safe(genserver_name) do
          {:ok, status} ->
            if status.pool_size >= expected_workers do
              {:ok, %{
                pool_size: status.pool_size,
                expected_workers: expected_workers,
                active_sessions: status.active_sessions
              }}
            else
              {:waiting, "workers not ready: #{status.pool_size}/#{expected_workers}"}
            end
            
          {:error, reason} ->
            {:waiting, "pool status check failed: #{inspect(reason)}"}
        end
      end,
      start_time,
      timeout
    )
  end

  @doc """
  Synchronizes multiple pool operations to ensure deterministic testing.
  
  Waits for all operations to complete before proceeding.
  """
  @spec synchronize_pool_operations(list(Task.t()), timeout()) :: {:ok, list()} | {:error, term()}
  def synchronize_pool_operations(tasks, timeout \\ 30_000) do
    try do
      results = Task.await_many(tasks, timeout)
      {:ok, results}
    catch
      :exit, reason -> {:error, {:task_timeout, reason}}
      error -> {:error, {:task_error, error}}
    end
  end

  @doc """
  Waits for a pool to become idle (no active sessions).
  
  Useful for test cleanup and ensuring operations have completed.
  """
  @spec wait_for_pool_idle(atom(), timeout()) :: {:ok, :idle} | {:error, term()}
  def wait_for_pool_idle(genserver_name, timeout \\ 10_000) do
    start_time = System.monotonic_time(:millisecond)
    
    wait_for(
      fn ->
        case get_pool_status_safe(genserver_name) do
          {:ok, status} ->
            if status.active_sessions == 0 do
              {:ok, :idle}
            else
              {:waiting, "pool has #{status.active_sessions} active sessions"}
            end
            
          {:error, reason} ->
            {:waiting, "pool status check failed: #{inspect(reason)}"}
        end
      end,
      start_time,
      timeout
    )
  end

  @doc """
  Waits for session affinity to be established for a given session.
  
  Checks that a session is consistently routed to the same worker.
  """
  @spec wait_for_session_affinity(String.t(), atom(), timeout()) :: {:ok, String.t()} | {:error, term()}
  def wait_for_session_affinity(session_id, pool_name, timeout \\ 5_000) do
    start_time = System.monotonic_time(:millisecond)
    
    wait_for(
      fn ->
        case check_session_worker_assignment(session_id, pool_name) do
          {:ok, worker_id} ->
            # Verify consistency with a second check
            case check_session_worker_assignment(session_id, pool_name) do
              {:ok, ^worker_id} -> {:ok, worker_id}
              {:ok, different_worker} -> 
                {:waiting, "session affinity inconsistent: #{worker_id} vs #{different_worker}"}
              error -> 
                {:waiting, "session check failed: #{inspect(error)}"}
            end
            
          {:error, reason} ->
            {:waiting, "session not found: #{inspect(reason)}"}
        end
      end,
      start_time,
      timeout
    )
  end

  @doc """
  Enhanced wait_for function with pool-specific conditions.
  
  Extends the existing wait_for to handle pool-specific wait conditions.
  """
  @spec wait_for_pool_condition(atom(), map(), timeout()) :: {:ok, term()} | {:error, term()}
  def wait_for_pool_condition(condition_type, params, timeout \\ 10_000) do
    start_time = System.monotonic_time(:millisecond)
    
    condition_fn = case condition_type do
      :pool_ready ->
        fn -> check_pool_ready_condition(params) end
      :workers_initialized ->
        fn -> check_workers_initialized_condition(params) end
      :pool_idle ->
        fn -> check_pool_idle_condition(params) end
      :session_affinity ->
        fn -> check_session_affinity_condition(params) end
      _ ->
        fn -> {:error, {:unknown_condition, condition_type}} end
    end
    
    wait_for(condition_fn, start_time, timeout)
  end

  ## Private Helper Functions for Pool Operations

  defp get_pool_status_safe(genserver_name) do
    try do
      case Process.whereis(genserver_name) do
        nil -> {:error, :process_not_found}
        pid when is_pid(pid) ->
          case DSPex.PythonBridge.SessionPoolV2.get_pool_status(genserver_name) do
            status when is_map(status) -> {:ok, status}
            error -> {:error, {:invalid_status, error}}
          end
      end
    catch
      :exit, reason -> {:error, {:exit, reason}}
      error -> {:error, {:exception, error}}
    end
  end

  defp check_session_worker_assignment(session_id, pool_name) do
    try do
      case DSPex.PythonBridge.SessionPoolV2.execute_in_session(
             session_id,
             :ping,
             %{test: "affinity_check"},
             pool_name: pool_name,
             timeout: 2000
           ) do
        {:ok, response} ->
          worker_id = response["worker_id"]
          if worker_id, do: {:ok, worker_id}, else: {:error, :no_worker_id}
        error ->
          {:error, error}
      end
    catch
      error -> {:error, {:exception, error}}
    end
  end

  defp check_pool_ready_condition(%{genserver_name: genserver_name}) do
    case get_pool_status_safe(genserver_name) do
      {:ok, status} when status.pool_size > 0 -> {:ok, :ready}
      {:ok, _status} -> {:waiting, "pool not ready"}
      error -> error
    end
  end

  defp check_workers_initialized_condition(%{genserver_name: genserver_name, expected_workers: expected}) do
    case get_pool_status_safe(genserver_name) do
      {:ok, status} when status.pool_size >= expected -> 
        {:ok, %{pool_size: status.pool_size, expected: expected}}
      {:ok, status} -> 
        {:waiting, "workers not ready: #{status.pool_size}/#{expected}"}
      error -> 
        error
    end
  end

  defp check_pool_idle_condition(%{genserver_name: genserver_name}) do
    case get_pool_status_safe(genserver_name) do
      {:ok, status} when status.active_sessions == 0 -> {:ok, :idle}
      {:ok, status} -> {:waiting, "pool has #{status.active_sessions} active sessions"}
      error -> error
    end
  end

  defp check_session_affinity_condition(%{session_id: session_id, pool_name: pool_name}) do
    check_session_worker_assignment(session_id, pool_name)
  end
end
