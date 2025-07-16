defmodule DSPex.PythonBridge.PoolWorkerV2 do
  @moduledoc """
  Simplified NimblePool worker implementation for Python bridge processes.

  This version removes unnecessary response handling logic since clients
  communicate directly with ports after checkout.

  Key differences from V1:
  - No send_command/4 public function
  - No response handling in handle_info/2
  - Simplified to just manage worker lifecycle
  - Raises on init failure instead of returning error tuple
  """

  @behaviour NimblePool

  alias DSPex.PythonBridge.Protocol
  require Logger

  # Worker state structure
  defstruct [
    :port,
    :python_path,
    :script_path,
    :worker_id,
    # Kept for compatibility but not used for session binding
    :current_session,
    :stats,
    :health_status,
    :started_at,
    # Failure tracking for worker lifecycle management
    consecutive_failures: 0,
    last_failure_time: nil,
    failure_threshold: 3
  ]

  ## NimblePool Callbacks

  @impl NimblePool
  def init_worker(pool_state) do
    worker_id = generate_worker_id()
    Logger.debug("Initializing pool worker: #{worker_id}")

    # Get Python environment details - cached after first validation
    case get_cached_environment_info() do
      {:ok, env_info} ->
        python_path = env_info.python_path
        script_path = env_info.script_path

        # Start Python process in pool-worker mode
        # Note: :stderr_to_stdout can interfere with packet mode if Python prints to stderr
        # Enable it conditionally for debugging
        debug_mode = Application.get_env(:dspex, :pool_debug_mode, false)

        base_opts = [
          :binary,
          :exit_status,
          {:packet, 4},
          {:args, [script_path, "--mode", "pool-worker", "--worker-id", worker_id]}
        ]

        port_opts =
          if debug_mode do
            Logger.warning(
              "Pool debug mode enabled - stderr will be captured (may interfere with packet mode)"
            )

            [:stderr_to_stdout | base_opts]
          else
            base_opts
          end

        Logger.debug("Starting Python process for worker #{worker_id}")
        port = Port.open({:spawn_executable, python_path}, port_opts)

        # Initialize worker state
        worker_state = %__MODULE__{
          port: port,
          python_path: python_path,
          script_path: script_path,
          worker_id: worker_id,
          current_session: nil,
          stats: init_stats(),
          health_status: :initializing,
          started_at: System.monotonic_time(:millisecond)
        }

        # Send initialization ping to verify worker is ready
        Logger.info("About to send initialization ping for worker #{worker_id}")

        case send_initialization_ping(worker_state) do
          {:ok, updated_state} ->
            Logger.info("Pool worker #{worker_id} started successfully")
            {:ok, updated_state, pool_state}

          {:error, reason} ->
            Logger.error("Worker #{worker_id} initialization failed: #{inspect(reason)}")
            Port.close(port)
            raise "Worker #{worker_id} initialization failed: #{inspect(reason)}"
        end

      {:error, reason} ->
        Logger.error("Failed to validate Python environment: #{inspect(reason)}")
        raise "Failed to validate Python environment: #{inspect(reason)}"
    end
  end

  @impl NimblePool
  def handle_checkout(checkout_type, from, worker_state, pool_state) do
    case checkout_type do
      {:session, session_id} ->
        handle_session_checkout(session_id, from, worker_state, pool_state)

      :any_worker ->
        # In stateless architecture, any worker can handle any request
        handle_any_worker_checkout(from, worker_state, pool_state)

      :anonymous ->
        handle_anonymous_checkout(from, worker_state, pool_state)

      _ ->
        # NimblePool expects :remove or :skip, not :error
        {:remove, {:invalid_checkout_type, checkout_type}, pool_state}
    end
  end

  @impl NimblePool
  def handle_checkin(checkin_type, _from, worker_state, pool_state) do
    Logger.debug("Worker #{worker_state.worker_id} checkin with type: #{inspect(checkin_type)}")

    # Update stats
    updated_state = update_checkin_stats(worker_state, checkin_type)
    
    # Track failures or successes for recoverable errors
    final_state = case checkin_type do
      :ok -> 
        # Success - reset failure count
        updated_state
        |> Map.put(:consecutive_failures, 0)
        |> Map.put(:last_failure_time, nil)
      :error ->
        # Recoverable error - increment failure count
        current_time = :erlang.system_time(:millisecond)
        consecutive_failures = Map.get(updated_state, :consecutive_failures, 0) + 1
        
        updated_state
        |> Map.put(:consecutive_failures, consecutive_failures)
        |> Map.put(:last_failure_time, current_time)
      _ ->
        # Other types (like :close) - no change
        updated_state
    end

    # Determine if worker should be removed first
    if should_remove_worker?(final_state, checkin_type) do
      Logger.debug("Worker #{worker_state.worker_id} will be removed (failures: #{Map.get(final_state, :consecutive_failures, 0)})")
      {:remove, :closed, pool_state}
    else
      # Reconnect port to worker process to keep Python bridge alive
      case reconnect_port_to_worker(final_state) do
        :ok ->
          {:ok, final_state, pool_state}

        {:error, :port_already_closed} when checkin_type == :ok ->
          # For successful operations, port closure is non-fatal
          # The worker completed its task successfully, just spawn a new one
          Logger.info(
            "Worker #{worker_state.worker_id} port closed after successful operation, removing worker"
          )

          {:remove, :port_closed_after_success, pool_state}

        {:error, :port_closed_during_connect} when checkin_type == :ok ->
          # For successful operations, port closure is non-fatal
          # The worker completed its task successfully, just spawn a new one
          Logger.info(
            "Worker #{worker_state.worker_id} port closed during reconnect after successful operation, removing worker"
          )

          {:remove, :port_closed_after_success, pool_state}

        {:error, :port_closed} when checkin_type == :ok ->
          # For successful operations, port closure is non-fatal
          # The worker completed its task successfully, just spawn a new one
          Logger.info(
            "Worker #{worker_state.worker_id} port closed after successful operation, removing worker"
          )

          {:remove, :port_closed_after_success, pool_state}

        {:error, reason} ->
          Logger.error(
            "Worker #{worker_state.worker_id} port reconnection failed: #{inspect(reason)}"
          )

          {:remove, {:port_reconnect_failed, reason}, pool_state}
      end
    end
  end

  @impl NimblePool
  def handle_info(message, worker_state) do
    case message do
      # Port died unexpectedly
      {port, {:exit_status, status}} when port == worker_state.port ->
        Logger.error("Python worker #{worker_state.worker_id} exited with status: #{status}")
        {:remove, :port_exited}

      # Ignore other messages - responses are handled by clients
      _ ->
        {:ok, worker_state}
    end
  end

  @impl NimblePool
  def terminate_worker(reason, worker_state, pool_state) do
    Logger.info("Terminating pool worker #{worker_state.worker_id}, reason: #{inspect(reason)}")

    # Send shutdown command to Python process
    try do
      send_shutdown_command(worker_state)

      # Give Python process time to cleanup
      # Wait for port to exit or force close
      ref = Process.monitor(worker_state.port)

      receive do
        {port, {:exit_status, _}} when port == worker_state.port ->
          Process.demonitor(ref, [:flush])
          :ok

        {:DOWN, ^ref, :port, _, _} ->
          :ok
      after
        1000 ->
          Process.demonitor(ref, [:flush])
          # Force close if not exited
          try do
            Port.close(worker_state.port)
          catch
            :error, _ -> :ok
          end
      end
    catch
      :error, _ ->
        # Port already closed
        :ok
    end

    {:ok, pool_state}
  end

  ## Checkout Handlers

  defp handle_session_checkout(session_id, {pid, _ref}, worker_state, pool_state) do
    # Stateless workers - any worker can handle any session using centralized SessionStore
    updated_state = %{
      worker_state
      | # Track current session for logging
        current_session: session_id,
        stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
    }

    # Use safe port connection
    case safe_port_connect(worker_state.port, pid, worker_state.worker_id) do
      {:ok, _port} ->
        # Return worker state as client state
        {:ok, updated_state, updated_state, pool_state}

      {:error, :not_a_pid} ->
        Logger.error(
          "[#{worker_state.worker_id}] Invalid PID type during checkout: #{inspect(pid)}"
        )

        {:remove, {:checkout_failed, :invalid_pid}, pool_state}

      {:error, :process_not_alive} ->
        Logger.error(
          "[#{worker_state.worker_id}] Target process not alive during checkout: #{inspect(pid)}"
        )

        {:remove, {:checkout_failed, :process_not_alive}, pool_state}

      {:error, :port_closed_during_connect} ->
        Logger.error("[#{worker_state.worker_id}] Port closed during checkout")
        {:remove, {:checkout_failed, :port_closed_during_connect}, pool_state}

      {:error, {:connect_failed, reason}} ->
        Logger.error("[#{worker_state.worker_id}] Port connection failed: #{inspect(reason)}")
        {:remove, {:checkout_failed, {:connect_failed, reason}}, pool_state}

      {:error, reason} ->
        Logger.error("[#{worker_state.worker_id}] Port connection failed: #{inspect(reason)}")
        {:remove, {:checkout_failed, reason}, pool_state}
    end
  end

  defp handle_any_worker_checkout({pid, _ref}, worker_state, pool_state) do
    # In stateless architecture, any worker can handle any request
    # No session binding required - worker will fetch session data on demand
    updated_state = %{
      worker_state
      | # No session binding in stateless architecture
        current_session: nil,
        stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
    }

    # Use safe port connection
    case safe_port_connect(worker_state.port, pid, worker_state.worker_id) do
      {:ok, _port} ->
        # Return worker state as client state
        {:ok, updated_state, updated_state, pool_state}

      {:error, :not_a_pid} ->
        Logger.error(
          "[#{worker_state.worker_id}] Invalid PID type during any_worker checkout: #{inspect(pid)}"
        )

        {:remove, {:checkout_failed, :invalid_pid}, pool_state}

      {:error, :process_not_alive} ->
        Logger.error(
          "[#{worker_state.worker_id}] Target process not alive during any_worker checkout: #{inspect(pid)}"
        )

        {:remove, {:checkout_failed, :process_not_alive}, pool_state}

      {:error, :port_closed_during_connect} ->
        Logger.error("[#{worker_state.worker_id}] Port closed during any_worker checkout")
        {:remove, {:checkout_failed, :port_closed_during_connect}, pool_state}

      {:error, {:connect_failed, reason}} ->
        Logger.error(
          "[#{worker_state.worker_id}] Port connection failed during any_worker checkout: #{inspect(reason)}"
        )

        {:remove, {:checkout_failed, {:connect_failed, reason}}, pool_state}

      {:error, reason} ->
        Logger.error(
          "[#{worker_state.worker_id}] Port connection failed during any_worker checkout: #{inspect(reason)}"
        )

        {:remove, {:checkout_failed, reason}, pool_state}
    end
  end

  defp handle_anonymous_checkout({pid, _ref}, worker_state, pool_state) do
    # Anonymous checkout - no session binding
    updated_state = %{
      worker_state
      | stats: Map.update(worker_state.stats, :checkouts, 1, &(&1 + 1))
    }

    # Use safe port connection
    case safe_port_connect(worker_state.port, pid, worker_state.worker_id) do
      {:ok, _port} ->
        # Return worker state as client state
        {:ok, updated_state, updated_state, pool_state}

      {:error, :not_a_pid} ->
        Logger.error(
          "[#{worker_state.worker_id}] Invalid PID type during anonymous checkout: #{inspect(pid)}"
        )

        {:remove, {:checkout_failed, :invalid_pid}, pool_state}

      {:error, :process_not_alive} ->
        Logger.error(
          "[#{worker_state.worker_id}] Target process not alive during anonymous checkout: #{inspect(pid)}"
        )

        {:remove, {:checkout_failed, :process_not_alive}, pool_state}

      {:error, :port_closed_during_connect} ->
        Logger.error("[#{worker_state.worker_id}] Port closed during anonymous checkout")
        {:remove, {:checkout_failed, :port_closed_during_connect}, pool_state}

      {:error, {:connect_failed, reason}} ->
        Logger.error(
          "[#{worker_state.worker_id}] Port connection failed during anonymous checkout: #{inspect(reason)}"
        )

        {:remove, {:checkout_failed, {:connect_failed, reason}}, pool_state}

      {:error, reason} ->
        Logger.error(
          "[#{worker_state.worker_id}] Port connection failed during anonymous checkout: #{inspect(reason)}"
        )

        {:remove, {:checkout_failed, reason}, pool_state}
    end
  end

  ## Initialization

  defp send_initialization_ping(worker_state) do
    # Special ID for init ping
    request_id = 0

    request =
      Protocol.encode_request(request_id, :ping, %{
        initialization: true,
        worker_id: worker_state.worker_id
      })

    Logger.info("Sending init ping request: #{inspect(request)}")
    Logger.info("Request byte size: #{byte_size(request)}")
    Logger.info("To port: #{inspect(worker_state.port)}")

    try do
      # Use Port.command/2 for packet mode ports, not send/2
      result = Port.command(worker_state.port, request)
      Logger.info("Port.command result: #{inspect(result)}")

      # Wait for response with proper message filtering
      wait_for_init_response(worker_state, request_id)
    catch
      :error, reason ->
        Logger.error("Failed to send init ping: #{inspect(reason)}")
        {:error, {:send_failed, reason}}
    end
  end

  defp wait_for_init_response(worker_state, request_id) do
    receive do
      {port, {:data, data}} when port == worker_state.port ->
        Logger.debug("Received init response data: #{inspect(data, limit: :infinity)}")
        Logger.debug("Data byte size: #{byte_size(data)}")

        case Protocol.decode_response(data) do
          {:ok, ^request_id, response} ->
            Logger.debug("Decoded init response: #{inspect(response)}")

            # Protocol.decode_response already extracts the result field
            # so 'response' here is the content of the "result" field
            case response do
              %{"status" => "ok"} ->
                Logger.debug("Init ping successful")
                {:ok, %{worker_state | health_status: :healthy}}

              response_map when is_map(response_map) ->
                # Any map response is considered success for init
                Logger.debug("Init ping successful with response: #{inspect(response_map)}")
                {:ok, %{worker_state | health_status: :healthy}}

              _ ->
                Logger.error("Unexpected response structure: #{inspect(response)}")
                {:error, :malformed_init_response}
            end

          {:ok, other_id, _response} ->
            Logger.error("Init response ID mismatch: expected 0, got #{other_id}")
            {:error, :response_id_mismatch}

          {:error, _id, error_msg} ->
            Logger.error("Init ping returned error: #{error_msg}")
            {:error, {:init_failed, error_msg}}

          {:error, reason} ->
            Logger.error("Failed to decode init response: #{inspect(reason)}")
            {:error, {:decode_error, reason}}
        end

      {port, {:exit_status, status}} when port == worker_state.port ->
        Logger.error("Port exited during init with status #{status}")
        {:error, {:port_exited, status}}

      {:EXIT, _pid, _reason} ->
        # Ignore EXIT messages from other processes during init
        Logger.debug("Ignoring EXIT message during init, continuing to wait...")
        # Continue waiting for our response
        wait_for_init_response(worker_state, request_id)

      {:"$gen_call", _from, {:checkout, _checkout_type, _opts}} = checkout_msg ->
        # Buffer checkout requests during initialization instead of logging warnings
        # This prevents message queue pollution
        Logger.debug("Buffering checkout request during initialization")
        # Put the message back in the mailbox for later processing
        send(self(), checkout_msg)
        # Continue waiting for our response
        wait_for_init_response(worker_state, request_id)

      other ->
        Logger.debug("Unexpected message during init: #{inspect(other)}, continuing to wait...")
        # Continue waiting for our response
        wait_for_init_response(worker_state, request_id)
    after
      10000 ->
        Logger.error("Init ping timeout after 10 seconds for worker #{worker_state.worker_id}")
        # Check if port is still alive
        port_info = Port.info(worker_state.port)
        Logger.error("Port info at timeout: #{inspect(port_info)}")
        {:error, :init_timeout}
    end
  end

  defp send_shutdown_command(worker_state) do
    request_id = System.unique_integer([:positive])

    request =
      Protocol.encode_request(request_id, :shutdown, %{
        worker_id: worker_state.worker_id
      })

    # Use Port.command/2 for packet mode ports
    Port.command(worker_state.port, request)
  end

  ## Stats Management

  defp init_stats do
    %{
      checkouts: 0,
      successful_checkins: 0,
      error_checkins: 0,
      uptime_ms: 0,
      last_activity: System.monotonic_time(:millisecond)
    }
  end

  defp update_checkin_stats(worker_state, checkin_type) do
    stats = worker_state.stats

    updated_stats =
      case checkin_type do
        :ok ->
          %{stats | successful_checkins: stats.successful_checkins + 1}

        {:error, _} ->
          %{stats | error_checkins: stats.error_checkins + 1}

        _ ->
          stats
      end

    %{
      worker_state
      | stats: Map.put(updated_stats, :last_activity, System.monotonic_time(:millisecond))
    }
  end

  defp should_remove_worker?(worker_state, checkin_type) do
    case checkin_type do
      :close -> true
      :error -> 
        # Check if worker has exceeded failure threshold
        consecutive_failures = Map.get(worker_state, :consecutive_failures, 0)
        failure_threshold = Map.get(worker_state, :failure_threshold, 3)
        consecutive_failures >= failure_threshold
      _ -> false
    end
  end

  ## Utility Functions

  defp generate_worker_id do
    "worker_#{:erlang.unique_integer([:positive])}_#{:erlang.system_time(:microsecond)}"
  end

  # Remove @doc since this is a private function
  @spec validate_port(port()) :: {:ok, port()} | {:error, atom()}
  defp validate_port(port) when is_port(port) do
    case Port.info(port) do
      nil ->
        {:error, :port_closed}

      _port_info ->
        # For pool workers, we just need to verify the port is open
        # The port will be connected to different processes during checkout
        {:ok, port}
    end
  end

  defp validate_port(_), do: {:error, :not_a_port}

  # Safely connects a port to a target process with full validation
  @spec safe_port_connect(port(), pid(), String.t()) :: {:ok, port()} | {:error, term()}
  defp safe_port_connect(port, target_pid, worker_id) do
    Logger.debug("[#{worker_id}] Attempting safe port connection to #{inspect(target_pid)}")

    # Validate inputs
    with :ok <- validate_pid(target_pid),
         {:ok, _port} <- validate_port(port),
         :ok <- attempt_port_connect(port, target_pid, worker_id) do
      {:ok, port}
    else
      {:error, reason} = error ->
        Logger.error("[#{worker_id}] Safe port connect failed: #{inspect(reason)}")
        error
    end
  end

  defp validate_pid(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      :ok
    else
      {:error, :process_not_alive}
    end
  end

  defp validate_pid(_), do: {:error, :not_a_pid}

  defp attempt_port_connect(port, target_pid, worker_id) do
    try do
      Port.connect(port, target_pid)
      Logger.debug("[#{worker_id}] Successfully connected port to #{inspect(target_pid)}")
      :ok
    rescue
      ArgumentError ->
        # This can happen if the port was closed between validation and connect
        {:error, :port_closed_during_connect}
    catch
      :error, :badarg ->
        {:error, :badarg}

      :error, reason ->
        {:error, {:connect_failed, reason}}
    end
  end

  # Reconnects the port back to the worker process to keep Python bridge alive
  defp reconnect_port_to_worker(worker_state) do
    worker_pid = self()

    # First check if port is still alive
    case Port.info(worker_state.port) do
      nil ->
        Logger.warning("[#{worker_state.worker_id}] Port already closed, cannot reconnect")
        {:error, :port_already_closed}

      port_info ->
        Logger.debug(
          "[#{worker_state.worker_id}] Port info before reconnect: #{inspect(port_info)}"
        )

        # Attempt reconnection with retry for transient failures
        reconnect_port_to_worker_with_retry(worker_state, worker_pid, 3)
    end
  end

  defp reconnect_port_to_worker_with_retry(worker_state, worker_pid, attempts) do
    case safe_port_connect(worker_state.port, worker_pid, worker_state.worker_id) do
      {:ok, _port} ->
        Logger.debug("[#{worker_state.worker_id}] Port reconnected to worker process")
        :ok

      {:error, :port_closed} when attempts > 1 ->
        # Retry immediately for transient port issues
        reconnect_port_to_worker_with_retry(worker_state, worker_pid, attempts - 1)

      {:error, :port_closed_during_connect} when attempts > 1 ->
        # Retry immediately for transient port issues
        reconnect_port_to_worker_with_retry(worker_state, worker_pid, attempts - 1)

      {:error, reason} ->
        Logger.debug(
          "[#{worker_state.worker_id}] Port reconnection failed after #{4 - attempts} attempts: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Gets the current state and statistics of the worker.
  Used for monitoring and debugging.
  """
  def get_worker_info(worker_state) do
    %{
      worker_id: worker_state.worker_id,
      current_session: worker_state.current_session,
      health_status: worker_state.health_status,
      stats: worker_state.stats,
      uptime_ms: System.monotonic_time(:millisecond) - worker_state.started_at
    }
  end

  ## Environment Validation Caching

  # ETS table for caching environment validation results
  @env_cache_table :dspex_env_cache

  defp get_cached_environment_info do
    _table = ensure_cache_table()

    case :ets.lookup(@env_cache_table, :env_info) do
      [{:env_info, env_info, timestamp}] ->
        # Cache is valid for 1 hour
        if System.os_time(:second) - timestamp < 3600 do
          Logger.debug("Using cached environment validation")
          {:ok, env_info}
        else
          validate_and_cache_environment()
        end

      [] ->
        validate_and_cache_environment()
    end
  end

  defp validate_and_cache_environment do
    # Use a global lock to prevent multiple workers from validating simultaneously
    :global.trans({:env_validation_lock, node()}, fn ->
      # Check cache again inside the lock
      case :ets.lookup(@env_cache_table, :env_info) do
        [{:env_info, env_info, timestamp}] ->
          if System.os_time(:second) - timestamp < 3600 do
            {:ok, env_info}
          else
            run_environment_validation()
          end
        [] ->
          run_environment_validation()
      end
    end)
  end

  defp run_environment_validation do
    Logger.info("Running environment validation (will be cached for subsequent workers)")

    case DSPex.PythonBridge.EnvironmentCheck.validate_environment() do
      {:ok, env_info} ->
        # Cache the result
        :ets.insert(@env_cache_table, {:env_info, env_info, System.os_time(:second)})
        {:ok, env_info}

      {:error, _reason} = error ->
        error
    end
  end

  defp ensure_cache_table do
    case :ets.whereis(@env_cache_table) do
      :undefined ->
        :ets.new(@env_cache_table, [:set, :public, :named_table])

      _tid ->
        :ok
    end
  end
end
