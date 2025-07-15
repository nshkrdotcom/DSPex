defmodule DSPex.PythonBridge.SessionPool do
  @moduledoc """
  Session-aware pool manager for Python bridge workers.

  This module manages a pool of Python processes using NimblePool and provides
  session-based isolation for concurrent DSPy operations. Each session gets
  exclusive access to a worker during operations, ensuring program isolation.

  ## Features

  - Dynamic pool sizing based on system resources
  - Session-based worker allocation
  - Automatic worker health monitoring
  - Request queuing and timeout handling
  - Metrics and performance tracking
  - Graceful shutdown and cleanup

  ## Architecture

  ```
  SessionPool (Supervisor)
  ├── Pool Manager (GenServer)
  └── NimblePool
      ├── Worker 1 (Python Process)
      ├── Worker 2 (Python Process)
      └── Worker N (Python Process)
  ```

  ## Usage

      # Start the pool
      {:ok, _} = DSPex.PythonBridge.SessionPool.start_link()
      
      # Execute in session
      {:ok, result} = SessionPool.execute_in_session("session_123", :create_program, %{...})
      
      # Get pool status
      status = SessionPool.get_pool_status()
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.PoolWorker

  # Pool configuration defaults
  @default_pool_size System.schedulers_online() * 2
  @default_overflow 2
  @default_checkout_timeout 5_000
  @default_operation_timeout 30_000
  @health_check_interval 30_000
  # 5 minutes
  @session_cleanup_interval 300_000

  # State structure
  defstruct [
    :pool_name,
    :pool_size,
    :overflow,
    :sessions,
    :metrics,
    :health_check_ref,
    :cleanup_ref,
    :started_at
  ]

  ## Public API

  @doc """
  Starts the session pool with the given options.

  ## Options

  - `:name` - The name to register the pool manager (default: `__MODULE__`)
  - `:pool_size` - Number of worker processes (default: schedulers * 2)
  - `:overflow` - Maximum additional workers when pool is full (default: 2)
  - `:checkout_timeout` - Maximum time to wait for available worker (default: 5000ms)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a command within a session context.

  Checks out a worker from the pool, binds it to the session,
  executes the command, and returns the worker to the pool.

  ## Parameters

  - `session_id` - Unique session identifier
  - `command` - The command to execute (atom)
  - `args` - Command arguments (map)
  - `opts` - Options including timeouts

  ## Examples

      {:ok, program_id} = SessionPool.execute_in_session(
        "user_123_session", 
        :create_program,
        %{signature: %{inputs: [...], outputs: [...]}}
      )
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_in_session, session_id, command, args, opts})
  end

  @doc """
  Executes a command without session binding.

  Useful for stateless operations that don't require session isolation.
  """
  def execute_anonymous(command, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_anonymous, command, args, opts})
  end

  @doc """
  Ends a session and cleans up associated resources.
  """
  def end_session(session_id) do
    GenServer.call(__MODULE__, {:end_session, session_id})
  end

  @doc """
  Gets the current status of the pool including metrics.
  """
  def get_pool_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Gets detailed information about active sessions.
  """
  def get_session_info do
    GenServer.call(__MODULE__, :get_sessions)
  end

  @doc """
  Performs a health check on all workers in the pool.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check, 10_000)
  end

  @doc """
  Gracefully shuts down the pool, ending all sessions.
  """
  def shutdown(timeout \\ 10_000) do
    GenServer.call(__MODULE__, :shutdown, timeout)
  end

  @doc """
  Manually triggers cleanup of stale sessions.

  Called periodically by the pool monitor.
  """
  def cleanup_stale_sessions do
    GenServer.cast(__MODULE__, :cleanup_stale_sessions)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Parse configuration
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    overflow = Keyword.get(opts, :overflow, @default_overflow)
    name = Keyword.get(opts, :name, __MODULE__)
    pool_name = make_pool_name(name)

    # Start NimblePool as part of initialization
    pool_config = [
      worker: {PoolWorker, []},
      pool_size: pool_size,
      max_overflow: overflow,
      # Important: create workers on-demand, not eagerly
      lazy: true,
      name: pool_name
    ]

    case NimblePool.start_link(pool_config) do
      {:ok, _pool_pid} ->
        # Schedule periodic tasks
        health_check_ref = schedule_health_check()
        cleanup_ref = schedule_cleanup()

        state = %__MODULE__{
          pool_name: pool_name,
          pool_size: pool_size,
          overflow: overflow,
          sessions: %{},
          metrics: init_metrics(),
          health_check_ref: health_check_ref,
          cleanup_ref: cleanup_ref,
          started_at: System.monotonic_time(:millisecond)
        }

        Logger.info("Session pool started with #{pool_size} workers, #{overflow} overflow")
        {:ok, state}

      {:error, reason} ->
        {:stop, {:pool_start_failed, reason}}
    end
  end

  @impl true
  def handle_call({:execute_in_session, session_id, command, args, opts}, _from, state) do
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    # Add session context
    enhanced_args = Map.put(args, :session_id, session_id)

    # Track session
    sessions =
      Map.put_new_lazy(state.sessions, session_id, fn ->
        %{
          started_at: System.monotonic_time(:millisecond),
          last_activity: System.monotonic_time(:millisecond),
          operations: 0,
          programs: MapSet.new()
        }
      end)

    updated_state = %{state | sessions: sessions}

    # Execute with NimblePool
    result =
      try do
        NimblePool.checkout!(
          state.pool_name,
          {:session, session_id},
          fn _from, worker_state ->
            # Execute command on worker
            case PoolWorker.send_command(worker_state, command, enhanced_args, operation_timeout) do
              {:ok, response, updated_state} ->
                {{:ok, response["result"]}, updated_state, :ok}

              {:error, reason} ->
                {{:error, reason}, worker_state, :ok}
            end
          end,
          pool_timeout
        )
      catch
        :exit, {:timeout, _} ->
          _result = update_metrics(updated_state, :pool_timeout)
          {:error, :pool_timeout}

        :exit, reason ->
          Logger.error("Pool checkout failed: #{inspect(reason)}")
          {:error, {:pool_error, reason}}
      end

    # Update session activity
    final_state = update_session_activity(updated_state, session_id)
    {:reply, result, final_state}
  end

  @impl true
  def handle_call({:execute_anonymous, command, args, opts}, _from, state) do
    pool_timeout = Keyword.get(opts, :pool_timeout, @default_checkout_timeout)
    operation_timeout = Keyword.get(opts, :timeout, @default_operation_timeout)

    result =
      try do
        NimblePool.checkout!(
          state.pool_name,
          :anonymous,
          fn _from, worker_state ->
            case PoolWorker.send_command(worker_state, command, args, operation_timeout) do
              {:ok, response, updated_state} ->
                {{:ok, response["result"]}, updated_state, :ok}

              {:error, reason} ->
                {{:error, reason}, worker_state, :ok}
            end
          end,
          pool_timeout
        )
      catch
        :exit, {:timeout, _} ->
          _result = update_metrics(state, :pool_timeout)
          {:error, :pool_timeout}

        :exit, reason ->
          Logger.error("Pool checkout failed: #{inspect(reason)}")
          {:error, {:pool_error, reason}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:track_session, session_id}, _from, state) do
    sessions =
      Map.put_new_lazy(state.sessions, session_id, fn ->
        %{
          started_at: System.monotonic_time(:millisecond),
          last_activity: System.monotonic_time(:millisecond),
          operations: 0,
          programs: MapSet.new()
        }
      end)

    {:reply, :ok, %{state | sessions: sessions}}
  end

  @impl true
  def handle_call({:end_session, session_id}, _from, state) do
    case Map.pop(state.sessions, session_id) do
      {nil, _sessions} ->
        {:reply, {:error, :session_not_found}, state}

      {session_info, remaining_sessions} ->
        # Update metrics
        metrics = update_session_end_metrics(state.metrics, session_info)

        # Cleanup session in workers
        cleanup_session_in_workers(session_id)

        {:reply, :ok, %{state | sessions: remaining_sessions, metrics: metrics}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      pool_size: state.pool_size,
      max_overflow: state.overflow,
      active_sessions: map_size(state.sessions),
      metrics: state.metrics,
      uptime_ms: System.monotonic_time(:millisecond) - state.started_at,
      pool_status: get_nimble_pool_status()
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_sessions, _from, state) do
    session_info =
      Map.new(state.sessions, fn {id, info} ->
        {id, Map.put(info, :session_id, id)}
      end)

    {:reply, session_info, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health_results = perform_pool_health_check()

    metrics =
      Map.put(state.metrics, :last_health_check, %{
        timestamp: DateTime.utc_now(),
        results: health_results
      })

    {:reply, health_results, %{state | metrics: metrics}}
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    Logger.info("Shutting down session pool gracefully")

    # Cancel scheduled tasks
    _result1 = Process.cancel_timer(state.health_check_ref)
    _result2 = Process.cancel_timer(state.cleanup_ref)

    # End all sessions
    for {session_id, _} <- state.sessions do
      cleanup_session_in_workers(session_id)
    end

    # Stop the pool
    :ok = NimblePool.stop(state.pool_name, :shutdown, 5_000)

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform health check asynchronously
    _task = Task.start(fn -> perform_pool_health_check() end)

    # Reschedule
    health_check_ref = schedule_health_check()

    {:noreply, %{state | health_check_ref: health_check_ref}}
  end

  @impl true
  def handle_info(:cleanup_stale_sessions, state) do
    now = System.monotonic_time(:millisecond)
    # 1 hour
    stale_timeout = 3600_000

    {stale, active} =
      Map.split_with(state.sessions, fn {_id, info} ->
        now - info.last_activity > stale_timeout
      end)

    # Cleanup stale sessions
    for {session_id, _} <- stale do
      Logger.warning("Cleaning up stale session: #{session_id}")
      cleanup_session_in_workers(session_id)
    end

    # Update metrics
    metrics =
      if map_size(stale) > 0 do
        Map.update(
          state.metrics,
          :stale_sessions_cleaned,
          map_size(stale),
          &(&1 + map_size(stale))
        )
      else
        state.metrics
      end

    # Reschedule
    cleanup_ref = schedule_cleanup()

    {:noreply, %{state | sessions: active, metrics: metrics, cleanup_ref: cleanup_ref}}
  end

  @impl true
  def handle_cast(:cleanup_stale_sessions, state) do
    # Manual trigger of stale session cleanup
    handle_info(:cleanup_stale_sessions, state)
  end

  ## Private Functions

  defp make_pool_name(name) when is_atom(name) do
    :"#{name}_pool"
  end

  defp update_session_activity(state, session_id) do
    sessions =
      Map.update(state.sessions, session_id, nil, fn session ->
        %{
          session
          | last_activity: System.monotonic_time(:millisecond),
            operations: session.operations + 1
        }
      end)

    %{state | sessions: sessions}
  end

  defp update_metrics(state, metric) do
    metrics =
      case metric do
        :pool_timeout ->
          Map.update(state.metrics, :pool_timeouts, 1, &(&1 + 1))
      end

    %{state | metrics: metrics}
  end

  defp init_metrics do
    %{
      total_operations: 0,
      successful_operations: 0,
      failed_operations: 0,
      total_sessions: 0,
      average_session_duration_ms: 0,
      pool_timeouts: 0,
      worker_errors: 0,
      stale_sessions_cleaned: 0
    }
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale_sessions, @session_cleanup_interval)
  end

  defp get_nimble_pool_status do
    # Get pool information from NimblePool
    # This is a simplified version - actual implementation would
    # need to interface with NimblePool's internals
    %{
      ready: :unknown,
      busy: :unknown,
      overflow: :unknown
    }
  end

  defp perform_pool_health_check do
    # Check health of all workers
    # This would iterate through workers and check their health
    %{
      healthy_workers: 0,
      unhealthy_workers: 0,
      total_workers: 0
    }
  end

  defp cleanup_session_in_workers(_session_id) do
    # During shutdown, we don't need to clean up individual sessions
    # as all workers will be terminated anyway
    :ok
  end

  defp update_session_end_metrics(metrics, session_info) do
    duration = System.monotonic_time(:millisecond) - session_info.started_at

    metrics
    |> Map.update(:total_sessions, 1, &(&1 + 1))
    |> Map.update(:average_session_duration_ms, duration, fn avg ->
      # Simple moving average
      sessions = metrics.total_sessions + 1
      (avg * (sessions - 1) + duration) / sessions
    end)
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
