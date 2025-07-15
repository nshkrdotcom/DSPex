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

  alias DSPex.PythonBridge.{
    PoolWorkerV2,
    PoolWorkerV2Enhanced,
    Protocol,
    SessionAffinity,
    PoolErrorHandler,
    CircuitBreaker,
    RetryLogic,
    ErrorRecoveryOrchestrator
  }

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
    :started_at,
    :worker_module
  ]

  ## Public API - Client Functions

  @doc """
  Executes a command within a session context with comprehensive error handling.

  This function runs in the CLIENT process, not the pool manager.
  It uses RetryLogic and PoolErrorHandler for robust error handling.
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    # Normalize opts to handle both maps and keyword lists
    normalized_opts = normalize_opts(opts)

    context = %{
      session_id: session_id,
      command: command,
      args: args,
      operation: :execute_command,
      adapter: __MODULE__
    }

    # Wrap entire operation in retry logic with circuit breaker protection
    retry_opts = [
      max_attempts: Keyword.get(normalized_opts, :max_retries, 3),
      circuit: :pool_operations,
      base_delay: 1_000,
      context: context
    ]

    RetryLogic.with_retry(
      fn ->
        do_execute_with_error_handling(session_id, command, args, normalized_opts, context)
      end,
      retry_opts
    )
  end

  @doc """
  Executes a command without session binding with error handling.

  This function runs in the CLIENT process for anonymous operations.
  """
  def execute_anonymous(command, args, opts \\ []) do
    # Normalize opts to handle both maps and keyword lists
    normalized_opts = normalize_opts(opts)

    context = %{
      command: command,
      args: args,
      operation: :execute_anonymous,
      adapter: __MODULE__
    }

    # Use retry logic for anonymous operations too
    retry_opts = [
      max_attempts: Keyword.get(normalized_opts, :max_retries, 2),
      circuit: :anonymous_operations,
      base_delay: 500,
      context: context
    ]

    RetryLogic.with_retry(
      fn -> do_execute_anonymous_with_error_handling(command, args, normalized_opts, context) end,
      retry_opts
    )
  end

  ## Private Error Handling Functions

  @spec do_execute_with_error_handling(String.t(), atom(), map(), keyword(), map()) ::
          {:ok, term()} | {:error, term()}
  defp do_execute_with_error_handling(session_id, command, args, opts, context) do
    opts = normalize_opts(opts)
    pool_name = Keyword.get(opts, :pool_name, get_default_pool_name())
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    # Track session
    track_session(session_id)

    try do
      NimblePool.checkout!(
        pool_name,
        {:session, session_id},
        fn from, worker ->
          execute_with_worker_error_handling(
            worker,
            command,
            args,
            operation_timeout,
            Map.merge(context, %{session_id: session_id, from: from})
          )
        end,
        pool_timeout
      )
    catch
      :exit, {:timeout, _} ->
        handle_pool_error({:timeout, :checkout_timeout}, context)

      :exit, {:noproc, _} ->
        handle_pool_error({:resource_error, :pool_not_available}, context)

      :exit, reason ->
        handle_pool_error({:system_error, reason}, context)

      kind, error ->
        handle_pool_error({:unexpected_error, {kind, error}}, context)
    end
  end

  @spec do_execute_anonymous_with_error_handling(atom(), map(), keyword(), map()) ::
          {:ok, term()} | {:error, term()}
  defp do_execute_anonymous_with_error_handling(command, args, opts, context) do
    opts = normalize_opts(opts)
    pool_name = Keyword.get(opts, :pool_name, get_default_pool_name())
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    try do
      NimblePool.checkout!(
        pool_name,
        :anonymous,
        fn from, worker ->
          execute_with_worker_error_handling(
            worker,
            command,
            args,
            operation_timeout,
            Map.merge(context, %{from: from})
          )
        end,
        pool_timeout
      )
    catch
      :exit, {:timeout, _} ->
        handle_pool_error({:timeout, :checkout_timeout}, context)

      :exit, reason ->
        handle_pool_error({:system_error, reason}, context)

      kind, error ->
        handle_pool_error({:unexpected_error, {kind, error}}, context)
    end
  end

  @spec execute_with_worker_error_handling(map(), atom(), map(), pos_integer(), map()) ::
          {{:ok, term()} | {:error, term()}, atom()}
  defp execute_with_worker_error_handling(worker, command, args, timeout, context) do
    enhanced_context =
      Map.merge(context, %{
        worker_id: worker.worker_id,
        worker_state: get_worker_state(worker)
      })

    # Generate request ID and encode
    request_id = System.unique_integer([:positive, :monotonic])

    enhanced_args =
      if session_id = Map.get(context, :session_id) do
        Map.put(args, :session_id, session_id)
      else
        args
      end

    try do
      request_payload = Protocol.encode_request(request_id, command, enhanced_args)

      # Record session affinity for enhanced workers
      if session_id = Map.get(context, :session_id) do
        bind_session_if_enhanced(session_id, worker)
      end

      # Send command to port
      port = worker.port
      Port.command(port, request_payload)

      # Wait for response with comprehensive error handling
      receive do
        {^port, {:data, data}} ->
          case Protocol.decode_response(data) do
            {:ok, ^request_id, response} when is_map(response) ->
              {{:ok, response}, :ok}

            {:ok, other_id, _} ->
              error = handle_response_mismatch(request_id, other_id, enhanced_context)
              {{:error, error}, :close}

            {:error, _id, reason} ->
              error =
                PoolErrorHandler.wrap_pool_error(
                  {:python_error, reason},
                  enhanced_context
                )

              {{:error, error}, :ok}

            {:error, reason} ->
              error = handle_decode_error(reason, enhanced_context)
              {{:error, error}, :close}
          end

        {^port, {:exit_status, status}} ->
          error = handle_port_exit(status, enhanced_context)
          {{:error, error}, :close}
      after
        timeout ->
          error = handle_command_timeout(worker, command, timeout, enhanced_context)
          {{:error, error}, :close}
      end
    catch
      :exit, {:timeout, _} ->
        error = handle_command_timeout(worker, command, timeout, enhanced_context)
        {{:error, error}, :close}

      :error, {:badarg, _} ->
        error =
          PoolErrorHandler.wrap_pool_error(
            {:command_send_failed, "Port.command/2 failed - port may be closed"},
            enhanced_context
          )

        {{:error, error}, :close}

      kind, error ->
        wrapped = handle_command_error(kind, error, enhanced_context)
        {{:error, wrapped}, :close}
    end
  end

  @spec handle_pool_error(term(), map()) :: {:ok, term()} | {:error, PoolErrorHandler.t()}
  defp handle_pool_error(error, context) do
    wrapped = PoolErrorHandler.wrap_pool_error(error, context)

    # Attempt recovery through orchestrator for critical errors
    case wrapped.severity do
      :critical ->
        case ErrorRecoveryOrchestrator.handle_error(wrapped, context) do
          {:ok, {:recovered, result}} ->
            Logger.info("Pool error recovered: #{wrapped.error_category}")
            {:ok, result}

          {:ok, {:failover, result}} ->
            Logger.warning("Pool operation succeeded through failover")
            {:ok, result}

          {:error, _recovery_error} ->
            Logger.error(
              "Pool error recovery failed: #{PoolErrorHandler.format_for_logging(wrapped)}"
            )

            {:error, wrapped}
        end

      _ ->
        Logger.warning("Pool error: #{PoolErrorHandler.format_for_logging(wrapped)}")
        {:error, wrapped}
    end
  end

  @spec handle_response_mismatch(non_neg_integer(), non_neg_integer(), %{
          adapter: DSPex.PythonBridge.SessionPoolV2,
          args: term(),
          command: term(),
          from: term(),
          operation: :execute_anonymous | :execute_command,
          worker_id: term(),
          worker_state: atom(),
          session_id: term()
        }) :: PoolErrorHandler.t()
  defp handle_response_mismatch(expected_id, actual_id, context) do
    PoolErrorHandler.wrap_pool_error(
      {:response_mismatch, "Expected ID #{expected_id}, got #{actual_id}"},
      Map.merge(context, %{expected_id: expected_id, actual_id: actual_id})
    )
  end

  @spec handle_decode_error(:binary_data | :decode_error | :malformed_response, %{
          adapter: DSPex.PythonBridge.SessionPoolV2,
          args: term(),
          command: term(),
          from: term(),
          operation: :execute_anonymous | :execute_command,
          worker_id: term(),
          worker_state: atom(),
          session_id: term()
        }) :: PoolErrorHandler.t()
  defp handle_decode_error(reason, context) do
    PoolErrorHandler.wrap_pool_error(
      {:decode_error, reason},
      Map.merge(context, %{decode_reason: reason})
    )
  end

  @spec handle_port_exit(integer(), map()) :: map()
  defp handle_port_exit(status, context) do
    # Record circuit breaker failure for port exits if available
    if circuit_breaker_available?() do
      CircuitBreaker.record_failure(:worker_ports, {:port_exit, status})
    end

    PoolErrorHandler.wrap_pool_error(
      {:port_exited, status},
      Map.merge(context, %{exit_status: status})
    )
  end

  @spec handle_command_timeout(map(), atom(), pos_integer(), map()) :: map()
  defp handle_command_timeout(worker, command, timeout, context) do
    Logger.error("Command timeout for worker #{worker.worker_id}: #{command} (#{timeout}ms)")

    # Record circuit breaker failure for timeouts if available
    if circuit_breaker_available?() do
      CircuitBreaker.record_failure(:worker_commands, :timeout)
    end

    PoolErrorHandler.wrap_pool_error(
      {:timeout, :command_timeout},
      Map.merge(context, %{
        worker_health: get_worker_health(worker),
        command_duration: timeout,
        timeout_ms: timeout
      })
    )
  end

  @spec handle_command_error(atom(), term(), map()) :: map()
  defp handle_command_error(kind, error, context) do
    Logger.error("Command error: #{kind} - #{inspect(error)}")

    PoolErrorHandler.wrap_pool_error(
      {:command_error, {kind, error}},
      Map.merge(context, %{error_kind: kind})
    )
  end

  @spec get_worker_state(map()) :: atom()
  defp get_worker_state(worker) do
    case Map.get(worker, :state_machine) do
      %{state: state} -> state
      _ -> :unknown
    end
  end

  @spec get_worker_health(map()) :: atom()
  defp get_worker_health(worker) do
    case Map.get(worker, :state_machine) do
      %{health: health} -> health
      _ -> :unknown
    end
  end

  @spec bind_session_if_enhanced(String.t(), map()) :: :ok
  defp bind_session_if_enhanced(session_id, worker) do
    if Map.has_key?(worker, :state_machine) do
      try do
        SessionAffinity.bind_session(session_id, worker.worker_id)
      rescue
        _ ->
          # SessionAffinity might not be running, that's ok for basic workers
          :ok
      end
    end

    :ok
  end

  @spec circuit_breaker_available?() :: boolean()
  defp circuit_breaker_available? do
    case Process.whereis(CircuitBreaker) do
      nil -> false
      _pid -> true
    end
  end

  ## Session Management Functions

  @doc """
  Tracks a session in ETS for monitoring.
  """
  def track_session(session_id) do
    _result = ensure_session_table()

    session_info = %{
      session_id: session_id,
      started_at: System.monotonic_time(:millisecond),
      last_activity: System.monotonic_time(:millisecond),
      operations: 0
    }

    _result = :ets.insert(@session_table, {session_id, session_info})
    :ok
  end

  @doc """
  Updates session activity timestamp.
  """
  def update_session_activity(session_id) do
    _result = ensure_session_table()

    case :ets.lookup(@session_table, session_id) do
      [{^session_id, info}] ->
        updated_info = %{
          info
          | last_activity: System.monotonic_time(:millisecond),
            operations: info.operations + 1
        }

        _result = :ets.insert(@session_table, {session_id, updated_info})
        :ok

      [] ->
        track_session(session_id)
    end
  end

  @doc """
  Ends a session and cleans up resources.
  """
  def end_session(session_id) do
    _result = ensure_session_table()
    _result = :ets.delete(@session_table, session_id)
    :ok
  end

  @doc """
  Gets information about active sessions.
  """
  def get_session_info do
    _result = ensure_session_table()

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
    _result = ensure_session_table()

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
          started_at: System.monotonic_time(:millisecond),
          worker_module: worker_module
        }

        worker_type = if worker_module == PoolWorkerV2Enhanced, do: "enhanced", else: "basic"

        Logger.info(
          "Session pool V2 started with #{pool_size} #{worker_type} workers, #{overflow} overflow"
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, {:pool_start_failed, reason}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    sessions = get_session_info()

    # Only get session affinity stats for enhanced workers
    affinity_stats =
      if state.worker_module == PoolWorkerV2Enhanced do
        try do
          SessionAffinity.get_stats()
        rescue
          _ -> %{}
        end
      else
        %{}
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

    _result = ensure_session_table()

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
      _result = :ets.delete(@session_table, session_id)
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
    _result1 = Process.cancel_timer(state.health_check_ref)
    _result2 = Process.cancel_timer(state.cleanup_ref)

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
    Enum.to_list(opts)
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
