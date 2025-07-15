defmodule DSPex.PythonBridge.SessionAffinity do
  @moduledoc """
  Manages session-to-worker affinity for consistent routing.

  This module provides a fast, ETS-based session affinity system that ensures
  sessions are consistently routed to the same worker when possible. This is
  important for maintaining state and optimizing performance.

  ## Features

  - Fast ETS-based session tracking
  - Automatic cleanup of expired sessions
  - Worker removal handling
  - Configurable session timeouts
  - Concurrent access optimized

  ## Usage

      # Start the affinity manager
      {:ok, _} = SessionAffinity.start_link([])
      
      # Bind a session to a worker
      :ok = SessionAffinity.bind_session("session_123", "worker_456")
      
      # Get worker for session
      {:ok, "worker_456"} = SessionAffinity.get_worker("session_123")
      
      # Clean up when session ends
      :ok = SessionAffinity.unbind_session("session_123")
  """

  use GenServer
  require Logger

  @table_name :dspex_session_affinity
  # 1 minute
  @cleanup_interval 60_000
  # 5 minutes
  @session_timeout 300_000

  ## Public API

  @doc """
  Starts the session affinity manager.

  ## Options

  - `:cleanup_interval` - How often to run cleanup (default: 60 seconds)
  - `:session_timeout` - Session timeout (default: 5 minutes)
  - `:name` - Process name (default: `__MODULE__`)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Records a session-worker binding.

  ## Parameters

  - `session_id` - Unique session identifier
  - `worker_id` - Worker identifier to bind to the session

  ## Returns

  `:ok` always
  """
  @spec bind_session(String.t(), String.t()) :: :ok
  def bind_session(session_id, worker_id) do
    timestamp = System.monotonic_time(:millisecond)
    safe_ets_insert(@table_name, {session_id, worker_id, timestamp})

    Logger.debug("Session #{session_id} bound to worker #{worker_id}")
    :ok
  end

  @doc """
  Retrieves the worker for a session.

  ## Parameters

  - `session_id` - Session identifier to look up

  ## Returns

  - `{:ok, worker_id}` if session exists and is not expired
  - `{:error, :session_expired}` if session exists but has expired
  - `{:error, :no_affinity}` if no binding exists
  """
  @spec get_worker(String.t(), atom()) ::
          {:ok, String.t()} | {:error, :session_expired | :no_affinity}
  def get_worker(session_id, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:get_worker, session_id})
  end

  @doc """
  Removes a session binding.

  ## Parameters

  - `session_id` - Session identifier to remove

  ## Returns

  `:ok` always
  """
  @spec unbind_session(String.t()) :: :ok
  def unbind_session(session_id) do
    safe_ets_delete(@table_name, session_id)

    Logger.debug("Session #{session_id} unbound")
    :ok
  end

  @doc """
  Removes all bindings for a worker.

  This is useful when a worker is being removed from the pool.

  ## Parameters

  - `worker_id` - Worker identifier to remove all sessions for

  ## Returns

  `:ok` always
  """
  @spec remove_worker_sessions(String.t()) :: :ok
  def remove_worker_sessions(worker_id) do
    # Find all sessions for this worker
    sessions =
      safe_ets_select(@table_name, [
        {{:"$1", worker_id, :"$3"}, [], [:"$1"]}
      ])

    # Remove them
    Enum.each(sessions, &safe_ets_delete(@table_name, &1))

    if length(sessions) > 0 do
      Logger.info("Removed #{length(sessions)} session bindings for worker #{worker_id}")
    end

    :ok
  end

  @doc """
  Gets statistics about current session affinity.

  ## Returns

  A map with affinity statistics:
  - `:total_sessions` - Number of active sessions
  - `:expired_sessions` - Number of expired sessions (cleaned up)
  - `:workers_with_sessions` - Number of unique workers with sessions
  """
  @spec get_stats() :: %{
          expired_sessions: non_neg_integer(),
          total_sessions: non_neg_integer(),
          workers_with_sessions: non_neg_integer()
        }
  def get_stats do
    all_sessions = safe_ets_tab2list(@table_name)
    now = System.monotonic_time(:millisecond)

    {active, expired} =
      Enum.split_with(all_sessions, fn {_, _, timestamp} ->
        not_expired?(timestamp, now)
      end)

    unique_workers =
      active
      |> Enum.map(fn {_, worker_id, _} -> worker_id end)
      |> Enum.uniq()
      |> length()

    %{
      total_sessions: length(active),
      expired_sessions: length(expired),
      workers_with_sessions: unique_workers
    }
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(opts) do
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @cleanup_interval)
    session_timeout = Keyword.get(opts, :session_timeout, @session_timeout)

    # Create ETS table safely in init (single-threaded)
    case :ets.whereis(@table_name) do
      :undefined ->
        _table =
          :ets.new(@table_name, [
            :named_table,
            :public,
            :set,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])

        Logger.debug("Created session affinity ETS table")

      _tid ->
        Logger.debug("Session affinity ETS table already exists")
    end

    # Schedule first cleanup
    schedule_cleanup(cleanup_interval)

    state = %{
      cleanup_interval: cleanup_interval,
      session_timeout: session_timeout,
      cleanup_count: 0,
      total_cleaned: 0
    }

    Logger.info(
      "Session affinity manager started with cleanup interval: #{cleanup_interval}ms, session timeout: #{session_timeout}ms"
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleaned_count = cleanup_expired_sessions(state.session_timeout)

    new_state = %{
      state
      | cleanup_count: state.cleanup_count + 1,
        total_cleaned: state.total_cleaned + cleaned_count
    }

    # Schedule next cleanup
    schedule_cleanup(state.cleanup_interval)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:get_internal_stats, _from, state) do
    stats =
      Map.merge(get_stats(), %{
        cleanup_runs: state.cleanup_count,
        total_sessions_cleaned: state.total_cleaned,
        session_timeout: state.session_timeout,
        cleanup_interval: state.cleanup_interval
      })

    {:reply, stats, state}
  end

  def handle_call({:get_worker, session_id}, _from, state) do
    result =
      case safe_ets_lookup(@table_name, session_id) do
        [{^session_id, worker_id, timestamp}] ->
          if not_expired_with_timeout?(timestamp, state.session_timeout) do
            Logger.debug("Session #{session_id} found bound to worker #{worker_id}")
            {:ok, worker_id}
          else
            Logger.debug("Session #{session_id} expired, removing binding")
            safe_ets_delete(@table_name, session_id)
            {:error, :session_expired}
          end

        [] ->
          Logger.debug("No affinity found for session #{session_id}")
          {:error, :no_affinity}
      end

    {:reply, result, state}
  end

  ## Private Functions

  # Safe ETS operations that handle table not existing
  defp safe_ets_insert(table, data) do
    try do
      :ets.insert(table, data)
    rescue
      ArgumentError ->
        Logger.warning("Session affinity table #{table} not available, operation skipped")
        false
    end
  end

  defp safe_ets_delete(table, key) do
    try do
      :ets.delete(table, key)
    rescue
      ArgumentError ->
        Logger.warning("Session affinity table #{table} not available, operation skipped")
        false
    end
  end

  defp safe_ets_lookup(table, key) do
    try do
      :ets.lookup(table, key)
    rescue
      ArgumentError ->
        Logger.warning("Session affinity table #{table} not available, returning empty result")
        []
    end
  end

  defp safe_ets_select(table, pattern) do
    try do
      :ets.select(table, pattern)
    rescue
      ArgumentError ->
        Logger.warning("Session affinity table #{table} not available, returning empty result")
        []
    end
  end

  defp safe_ets_tab2list(table) do
    try do
      :ets.tab2list(table)
    rescue
      ArgumentError ->
        Logger.warning("Session affinity table #{table} not available, returning empty result")
        []
    end
  end

  defp not_expired?(timestamp, now) do
    now - timestamp < @session_timeout
  end

  defp not_expired_with_timeout?(timestamp, session_timeout, now \\ nil) do
    now = now || System.monotonic_time(:millisecond)
    now - timestamp < session_timeout
  end

  defp cleanup_expired_sessions(session_timeout) do
    now = System.monotonic_time(:millisecond)
    expired_threshold = now - session_timeout

    # Find expired sessions
    expired =
      safe_ets_select(@table_name, [
        {{:"$1", :"$2", :"$3"}, [{:<, :"$3", expired_threshold}], [:"$1"]}
      ])

    # Remove expired sessions
    Enum.each(expired, &safe_ets_delete(@table_name, &1))

    if length(expired) > 0 do
      Logger.info("Cleaned up #{length(expired)} expired session affinity bindings")
    end

    length(expired)
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  ## Supervisor Integration

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
