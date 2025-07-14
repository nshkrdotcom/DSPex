defmodule DSPex.PythonBridge.SessionPoolV2 do
  @moduledoc """
  Refactored Session-aware pool manager for Python bridge workers.

  This version correctly implements the NimblePool pattern by moving blocking
  I/O operations to client processes instead of the pool manager GenServer.

  Key differences from V1:
  - execute_in_session/4 is a public function, not a GenServer call
  - Blocking receive operations happen in client processes
  - Direct port communication without intermediary functions
  - Simplified session tracking using ETS
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.{PoolWorkerV2, PoolWorkerV2Enhanced, Protocol, SessionAffinity}

  # Configuration defaults
  @default_pool_size System.schedulers_online() * 2
  @default_overflow 2
  @default_checkout_timeout 5_000
  @default_operation_timeout 30_000
  @health_check_interval 30_000
  @session_cleanup_interval 300_000

  # ETS table for session tracking
  @session_table :dspex_pool_sessions

  # State structure
  defstruct [
    :pool_name,
    :pool_pid,
    :pool_size,
    :overflow,
    :health_check_ref,
    :cleanup_ref,
    :started_at
  ]

  ## Public API - Client Functions

  @doc """
  Executes a command within a session context.

  This function runs in the CLIENT process, not the pool manager.
  It checks out a worker, performs the operation, and returns the worker.
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    opts = normalize_opts(opts)
    pool_name = Keyword.get(opts, :pool_name, get_default_pool_name())
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    # Track session
    track_session(session_id)

    # Generate request ID
    request_id = System.unique_integer([:positive, :monotonic])

    # Add session context to args
    enhanced_args = Map.put(args, :session_id, session_id)

    # Encode request once before checkout
    request_payload = Protocol.encode_request(request_id, command, enhanced_args)

    # Checkout and execute - THIS RUNS IN THE CLIENT PROCESS
    Logger.debug("Attempting to checkout from pool: #{inspect(pool_name)}")

    try do
      NimblePool.checkout!(
        pool_name,
        {:session, session_id},
        fn _from, worker_state ->
          Logger.debug("Successfully checked out worker: #{inspect(worker_state.worker_id)}")
          
          # Record session affinity for enhanced workers
          if Map.has_key?(worker_state, :state_machine) do
            try do
              SessionAffinity.bind_session(session_id, worker_state.worker_id)
            rescue
              _ -> 
                # SessionAffinity might not be running, that's ok for basic workers
                :ok
            end
          end
          
          # Get the port from worker state
          port = worker_state.port

          # Send command to port using Port.command/2 for packet mode
          unless Port.command(port, request_payload) do
            raise "Port.command/2 failed during session execution"
          end

          # Wait for response IN THE CLIENT PROCESS
          receive do
            {^port, {:data, data}} ->
              case Protocol.decode_response(data) do
                {:ok, ^request_id, response} ->
                  # Protocol.decode_response returns the content of "result" field
                  # so response is already the result
                  case response do
                    result when is_map(result) ->
                      {{:ok, result}, :ok}

                    _ ->
                      Logger.error("Malformed response: #{inspect(response)}")
                      {{:error, :malformed_response}, :close}
                  end

                {:ok, other_id, _} ->
                  Logger.error("Response ID mismatch: expected #{request_id}, got #{other_id}")
                  {{:error, :response_mismatch}, :close}

                {:error, _id, reason} ->
                  {{:error, reason}, :ok}

                {:error, reason} ->
                  Logger.error("Failed to decode response: #{inspect(reason)}")
                  {{:error, {:decode_error, reason}}, :close}
              end

            {^port, {:exit_status, status}} ->
              Logger.error("Port exited during operation with status: #{status}")
              exit({:port_died, status})
          after
            operation_timeout ->
              # Operation timed out - exit to trigger worker removal
              Logger.error("Operation timed out after #{operation_timeout}ms")
              exit({:timeout, "Operation timed out after #{operation_timeout}ms"})
          end
        end,
        pool_timeout
      )
    catch
      :exit, {:timeout, _} = reason ->
        {:error, {:pool_timeout, reason}}

      :exit, reason ->
        Logger.error("Checkout failed: #{inspect(reason)}")
        {:error, {:checkout_failed, reason}}
    end
  end

  @doc """
  Executes a command without session binding.

  This function runs in the CLIENT process for anonymous operations.
  """
  def execute_anonymous(command, args, opts \\ []) do
    opts = normalize_opts(opts)
    pool_name = Keyword.get(opts, :pool_name, get_default_pool_name())
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    # Generate request ID
    request_id = System.unique_integer([:positive, :monotonic])

    # Encode request
    request_payload = Protocol.encode_request(request_id, command, args)

    # Checkout and execute
    try do
      NimblePool.checkout!(
        pool_name,
        :anonymous,
        fn _from, worker_state ->
          Logger.debug("Checking out worker for anonymous execution")
          port = worker_state.port

          # Send command using Port.command/2 for packet mode
          Logger.debug("Sending command to port: #{inspect(port)}")

          unless Port.command(port, request_payload) do
            raise "Port.command/2 failed during anonymous execution"
          end

          Logger.debug("Waiting for response...")
          # Wait for response
          receive do
            {^port, {:data, data}} ->
              case Protocol.decode_response(data) do
                {:ok, ^request_id, response} ->
                  Logger.debug("Decoded response for request #{request_id}")
                  # Protocol.decode_response returns the content of "result" field
                  # so response is already the result, not the full response
                  case response do
                    result when is_map(result) ->
                      Logger.debug("Returning success result: #{inspect(result)}")
                      {{:ok, result}, :ok}

                    _ ->
                      Logger.error("Unexpected response format: #{inspect(response)}")
                      {{:error, :malformed_response}, :close}
                  end

                {:error, reason} ->
                  {{:error, reason}, :close}
              end

            {^port, {:exit_status, status}} ->
              exit({:port_died, status})
          after
            operation_timeout ->
              exit({:timeout, "Operation timed out"})
          end
        end,
        pool_timeout
      )
    catch
      :exit, reason ->
        {:error, reason}
    end
  end

  ## Session Management Functions

  @doc """
  Tracks a session in ETS for monitoring.
  """
  def track_session(session_id) do
    ensure_session_table()

    session_info = %{
      session_id: session_id,
      started_at: System.monotonic_time(:millisecond),
      last_activity: System.monotonic_time(:millisecond),
      operations: 0
    }

    :ets.insert(@session_table, {session_id, session_info})
    :ok
  end

  @doc """
  Updates session activity timestamp.
  """
  def update_session_activity(session_id) do
    ensure_session_table()

    case :ets.lookup(@session_table, session_id) do
      [{^session_id, info}] ->
        updated_info = %{
          info
          | last_activity: System.monotonic_time(:millisecond),
            operations: info.operations + 1
        }

        :ets.insert(@session_table, {session_id, updated_info})
        :ok

      [] ->
        track_session(session_id)
    end
  end

  @doc """
  Ends a session and cleans up resources.
  """
  def end_session(session_id) do
    ensure_session_table()
    :ets.delete(@session_table, session_id)
    :ok
  end

  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    ensure_session_table()

    :ets.tab2list(@session_table)
    |> Enum.map(fn {_id, info} -> info end)
  end

  ## Pool Management API (GenServer)

  @doc """
  Starts the session pool manager.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current pool status.
  """
  def get_pool_status(pool_name \\ __MODULE__) do
    GenServer.call(pool_name, :get_status)
  end

  @doc """
  Gets the actual pool name for a given GenServer name.
  """
  def get_pool_name_for(genserver_name \\ __MODULE__) do
    GenServer.call(genserver_name, :get_pool_name)
  end

  @doc """
  Performs a health check on the pool.
  """
  def health_check(pool_name \\ __MODULE__) do
    GenServer.call(pool_name, :health_check)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Initialize session tracking table
    ensure_session_table()

    # Start session affinity manager if enhanced workers are enabled
    worker_module = Keyword.get(opts, :worker_module, PoolWorkerV2)
    if worker_module == PoolWorkerV2Enhanced do
      case SessionAffinity.start_link(name: :"#{__MODULE__}_session_affinity") do
        {:ok, _} -> 
          Logger.info("Session affinity manager started for enhanced pool")
        {:error, {:already_started, _}} -> 
          Logger.debug("Session affinity manager already running")
        {:error, reason} -> 
          Logger.warning("Failed to start session affinity manager: #{inspect(reason)}")
      end
    end

    # Parse configuration
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    overflow = Keyword.get(opts, :overflow, @default_overflow)

    # Get name from opts or generate unique pool name
    genserver_name = Keyword.get(opts, :name, __MODULE__)
    pool_name = :"#{genserver_name}_pool"
    
    # Get lazy configuration from opts or app config
    lazy = Keyword.get(opts, :lazy, Application.get_env(:dspex, :pool_lazy, false))

    # Start NimblePool with configurable worker module
    pool_config = [
      worker: {worker_module, []},
      pool_size: pool_size,
      max_overflow: overflow,
      lazy: lazy,
      name: pool_name
    ]

    case NimblePool.start_link(pool_config) do
      {:ok, pool_pid} ->
        # Schedule periodic tasks
        health_check_ref = schedule_health_check()
        cleanup_ref = schedule_cleanup()

        state = %__MODULE__{
          pool_name: pool_name,
          pool_pid: pool_pid,
          pool_size: pool_size,
          overflow: overflow,
          health_check_ref: health_check_ref,
          cleanup_ref: cleanup_ref,
          started_at: System.monotonic_time(:millisecond)
        }

        worker_type = if worker_module == PoolWorkerV2Enhanced, do: "enhanced", else: "basic"
        Logger.info("Session pool V2 started with #{pool_size} #{worker_type} workers, #{overflow} overflow")
        {:ok, state}

      {:error, reason} ->
        {:stop, {:pool_start_failed, reason}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    sessions = get_session_info()
    
    # Try to get session affinity stats if available
    affinity_stats = try do
      SessionAffinity.get_stats()
    rescue
      _ -> %{}
    end

    status = %{
      pool_size: state.pool_size,
      max_overflow: state.overflow,
      active_sessions: length(sessions),
      sessions: sessions,
      uptime_ms: System.monotonic_time(:millisecond) - state.started_at,
      session_affinity: affinity_stats
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_pool_name, _from, state) do
    {:reply, state.pool_name, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    # For now, just return a simple status
    # In production, you'd check each worker's health
    {:reply, {:ok, :healthy}, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform periodic health check
    # In production, iterate through workers and check their health

    # Reschedule
    health_check_ref = schedule_health_check()
    {:noreply, %{state | health_check_ref: health_check_ref}}
  end

  @impl true
  def handle_info(:cleanup_stale_sessions, state) do
    # Clean up stale sessions from ETS
    now = System.monotonic_time(:millisecond)
    # 1 hour
    stale_timeout = 3600_000

    ensure_session_table()

    # Find and remove stale sessions
    stale_sessions =
      :ets.select(@session_table, [
        {
          {:"$1", %{last_activity: :"$2"}},
          [{:<, :"$2", now - stale_timeout}],
          [:"$1"]
        }
      ])

    Enum.each(stale_sessions, fn session_id ->
      Logger.warning("Cleaning up stale session: #{session_id}")
      :ets.delete(@session_table, session_id)
    end)

    # Reschedule
    cleanup_ref = schedule_cleanup()
    {:noreply, %{state | cleanup_ref: cleanup_ref}}
  end

  @impl true
  def handle_info({:replace_worker, worker_id, metadata}, state) do
    Logger.info("Received request to replace worker #{worker_id}: #{inspect(metadata)}")
    
    # NimblePool handles worker creation automatically when workers are removed
    # We just need to track metrics here
    
    # TODO: Add telemetry when available
    # :telemetry.execute(
    #   [:dspex, :pool, :worker, :replaced],
    #   %{count: 1},
    #   %{
    #     worker_id: worker_id,
    #     reason: Map.get(metadata, :reason, :unknown),
    #     pool_name: state.pool_name
    #   }
    # )
    
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel timers
    Process.cancel_timer(state.health_check_ref)
    Process.cancel_timer(state.cleanup_ref)

    # Stop the pool
    if state.pool_pid do
      NimblePool.stop(state.pool_name, :shutdown, 5_000)
    end

    :ok
  end

  ## Private Functions

  defp get_default_pool_name do
    :"#{__MODULE__}_pool"
  end

  defp normalize_opts(opts) when is_map(opts) do
    Enum.map(opts, fn {k, v} -> {k, v} end)
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(_), do: []

  defp ensure_session_table do
    case :ets.whereis(@session_table) do
      :undefined ->
        :ets.new(@session_table, [:set, :public, :named_table])

      _tid ->
        :ok
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale_sessions, @session_cleanup_interval)
  end

  ## Supervisor Integration

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end
end
