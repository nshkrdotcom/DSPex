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
    :current_session,
    :stats,
    :health_status,
    :started_at
  ]

  ## NimblePool Callbacks

  @impl NimblePool
  def init_worker(pool_state) do
    worker_id = generate_worker_id()
    Logger.debug("Initializing pool worker: #{worker_id}")

    # Get Python environment details
    case DSPex.PythonBridge.EnvironmentCheck.validate_environment() do
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

    # Determine if worker should be removed
    case should_remove_worker?(updated_state, checkin_type) do
      true ->
        Logger.debug("Worker #{worker_state.worker_id} will be removed")
        {:remove, :closed, pool_state}

      false ->
        {:ok, updated_state, pool_state}
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
      receive do
        {port, {:exit_status, _}} when port == worker_state.port ->
          :ok
      after
        1000 ->
          # Force close if not exited
          Port.close(worker_state.port)
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
    # Bind worker to session and update stats
    updated_state = %{
      worker_state
      | current_session: session_id,
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

      other ->
        Logger.warning("Unexpected message during init: #{inspect(other)}, continuing to wait...")
        # Continue waiting for our response
        wait_for_init_response(worker_state, request_id)
    after
      5000 ->
        Logger.error("Init ping timeout after 5 seconds for worker #{worker_state.worker_id}")
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

  defp should_remove_worker?(_worker_state, checkin_type) do
    case checkin_type do
      :close -> true
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
end
