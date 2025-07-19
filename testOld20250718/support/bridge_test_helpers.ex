defmodule DSPex.BridgeTestHelpers do
  @moduledoc """
  Test helpers for Python bridge communication.
  Provides event-driven coordination for bridge operations.

  Provides proper synchronization patterns following
  UNIFIED_TESTING_GUIDE.md principles.
  """

  require Logger
  import DSPex.SupervisionTestHelpers, only: [wait_for: 2]

  @doc """
  Performs a bridge call with retry logic and proper timeout handling.

  This replaces patterns where tests would wait for the bridge
  to be ready. Instead, it actively retries on failure with backoff.
  """
  @spec bridge_call_with_retry(pid() | atom(), atom(), map(), integer(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def bridge_call_with_retry(bridge_pid, command, args, retries \\ 3, timeout \\ 2000) do
    bridge_call_with_retry_loop(bridge_pid, command, args, retries, timeout, 1)
  end

  defp bridge_call_with_retry_loop(bridge_pid, command, args, retries, timeout, attempt) do
    case safe_bridge_call(bridge_pid, command, args, timeout) do
      {:ok, result} ->
        {:ok, result}

      {:error, :timeout} when attempt < retries ->
        Logger.debug("Bridge call timeout, attempt #{attempt}/#{retries}, retrying...")
        # Wait for bridge to potentially recover
        case wait_for_bridge_recovery(bridge_pid, 1000) do
          :ok ->
            bridge_call_with_retry_loop(bridge_pid, command, args, retries, timeout, attempt + 1)

          error ->
            error
        end

      {:error, reason} when attempt < retries ->
        Logger.debug("Bridge call failed with #{inspect(reason)}, attempt #{attempt}/#{retries}")
        bridge_call_with_retry_loop(bridge_pid, command, args, retries, timeout, attempt + 1)

      error ->
        error
    end
  end

  @doc """
  Performs a safe bridge call with proper error handling.

  Wraps GenServer.call with appropriate error catching and
  provides meaningful error responses.
  """
  @spec safe_bridge_call(pid() | atom(), atom(), map(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def safe_bridge_call(bridge_pid, command, args, timeout \\ 2000) do
    try do
      case GenServer.call(bridge_pid, {:call, command, args}, timeout) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        # Some calls might return direct results
        result -> {:ok, result}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, {:noproc, _} -> {:error, :bridge_not_running}
      :exit, reason -> {:error, {:exit, reason}}
      error -> {:error, error}
    end
  end

  @doc """
  Waits for a bridge to recover from an error state.

  Uses status polling with exponential backoff instead of fixed delays.
  """
  @spec wait_for_bridge_recovery(pid() | atom(), timeout()) :: :ok | {:error, term()}
  def wait_for_bridge_recovery(bridge_pid, timeout \\ 3000) do
    wait_for(
      fn ->
        case safe_get_bridge_status(bridge_pid) do
          {:ok, %{status: :running}} ->
            {:ok, :recovered}

          {:ok, %{status: status}} ->
            Logger.debug("Bridge status: #{status}, waiting for recovery...")
            nil

          {:error, :bridge_not_running} ->
            nil

          {:error, reason} ->
            Logger.debug("Bridge status check failed: #{inspect(reason)}")
            nil
        end
      end,
      timeout
    )
  end

  @doc """
  Safely gets bridge status without timing assumptions.

  Handles cases where the bridge might be starting, stopping, or crashed.
  """
  @spec safe_get_bridge_status(pid() | atom()) :: {:ok, map()} | {:error, term()}
  def safe_get_bridge_status(bridge_pid) do
    try do
      case GenServer.call(bridge_pid, :get_status, 1000) do
        status when is_map(status) -> {:ok, status}
        other -> {:error, {:invalid_status, other}}
      end
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, {:noproc, _} -> {:error, :bridge_not_running}
      :exit, reason -> {:error, {:exit, reason}}
      error -> {:error, error}
    end
  end

  @doc """
  Waits for a specific Python response by request ID.

  This is used when tests need to coordinate with asynchronous
  Python operations with proper coordination.
  """
  @spec wait_for_python_response(pid() | atom(), integer(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def wait_for_python_response(bridge_pid, request_id, timeout \\ 5000) do
    wait_for(
      fn ->
        case safe_bridge_call(bridge_pid, :get_response, %{request_id: request_id}, 100) do
          {:ok, response} -> {:ok, response}
          {:error, :not_ready} -> nil
          {:error, :not_found} -> nil
          error -> error
        end
      end,
      timeout
    )
  end

  @doc """
  Waits for bridge startup to complete.

  Checks both the GenServer state and Python process readiness.
  More reliable than arbitrary wait durations.
  """
  @spec wait_for_bridge_startup(pid() | atom(), timeout()) :: :ok | {:error, term()}
  def wait_for_bridge_startup(bridge_pid, timeout \\ 10000) do
    wait_for(
      fn ->
        case safe_get_bridge_status(bridge_pid) do
          {:ok, %{status: :running, python_ready: true}} ->
            {:ok, :ready}

          {:ok, %{status: :running}} ->
            # Bridge running but Python might not be ready
            case test_python_connectivity(bridge_pid) do
              {:ok, _} -> {:ok, :ready}
              _ -> nil
            end

          {:ok, %{status: status}} ->
            Logger.debug("Bridge status: #{status}, waiting for startup...")
            nil

          {:error, reason} ->
            Logger.debug("Bridge startup check failed: #{inspect(reason)}")
            nil
        end
      end,
      timeout
    )
  end

  @doc """
  Tests Python connectivity by sending a simple ping command.

  This verifies the entire communication stack is working,
  not just the GenServer state.
  """
  @spec test_python_connectivity(pid() | atom()) :: {:ok, term()} | {:error, term()}
  def test_python_connectivity(bridge_pid) do
    safe_bridge_call(bridge_pid, :ping, %{}, 2000)
  end

  @doc """
  Waits for bridge shutdown to complete.

  Monitors the process instead of guessing timing.
  """
  @spec wait_for_bridge_shutdown(pid(), timeout()) :: :ok | {:error, term()}
  def wait_for_bridge_shutdown(bridge_pid, timeout \\ 5000) when is_pid(bridge_pid) do
    ref = Process.monitor(bridge_pid)

    receive do
      {:DOWN, ^ref, :process, ^bridge_pid, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :shutdown_timeout}
    end
  end

  @doc """
  Creates a test bridge configuration with unique names.

  Prevents process name conflicts in parallel tests.
  """
  @spec test_bridge_config(map()) :: map()
  def test_bridge_config(overrides \\ %{}) do
    unique_id = :erlang.unique_integer([:positive])

    default_config = %{
      name: :"test_bridge_#{unique_id}",
      monitor_name: :"test_monitor_#{unique_id}",
      supervisor_name: :"test_supervisor_#{unique_id}",
      python_timeout: 5000,
      health_check_interval: 1000
    }

    Map.merge(default_config, overrides)
  end

  @doc """
  Performs a comprehensive bridge health check.

  Tests all aspects of bridge functionality:
  - GenServer responsiveness
  - Python process connectivity  
  - Command execution capability
  """
  @spec comprehensive_bridge_health_check(pid() | atom()) :: :ok | {:error, term()}
  def comprehensive_bridge_health_check(bridge_pid) do
    with {:ok, _status} <- safe_get_bridge_status(bridge_pid),
         {:ok, _ping_result} <- test_python_connectivity(bridge_pid),
         {:ok, _stats} <- safe_bridge_call(bridge_pid, :get_stats, %{}, 1000) do
      :ok
    else
      error -> error
    end
  end

  @doc """
  Waits for a specific number of commands to be processed.

  Useful for testing that async operations have completed
  without relying on timing assumptions.
  """
  @spec wait_for_command_count(pid() | atom(), integer(), timeout()) :: :ok | {:error, term()}
  def wait_for_command_count(bridge_pid, expected_count, timeout \\ 5000) do
    wait_for(
      fn ->
        case safe_bridge_call(bridge_pid, :get_stats, %{}, 1000) do
          {:ok, %{commands_processed: count}} when count >= expected_count ->
            {:ok, :reached}

          {:ok, %{commands_processed: count}} ->
            Logger.debug("Commands processed: #{count}/#{expected_count}")
            nil

          {:error, reason} ->
            Logger.debug("Failed to get command count: #{inspect(reason)}")
            nil
        end
      end,
      timeout
    )
  end

  @doc """
  Sets up a bridge for testing with proper isolation.

  Returns a configuration that can be used to start an isolated
  bridge instance for testing.
  """
  @spec setup_test_bridge(map()) :: {:ok, map()} | {:error, term()}
  def setup_test_bridge(config \\ %{}) do
    test_config = test_bridge_config(config)

    # Validate the configuration has required fields
    required_fields = [:name, :supervisor_name]
    missing_fields = required_fields -- Map.keys(test_config)

    if Enum.empty?(missing_fields) do
      {:ok, test_config}
    else
      {:error, {:missing_config_fields, missing_fields}}
    end
  end
end
