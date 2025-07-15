defmodule DSPex.PythonBridge.SessionStore do
  @moduledoc """
  Centralized session store using ETS for high-performance session management.

  This GenServer manages a centralized ETS table for storing session data,
  providing CRUD operations, TTL-based expiration, and automatic cleanup.
  The store is designed for high concurrency with optimized ETS settings.
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.Session

  @default_table_name :dspex_sessions
  # 1 minute
  @cleanup_interval 60_000
  # 1 hour
  @default_ttl 3600

  ## Client API

  @doc """
  Starts the SessionStore GenServer.

  ## Options

  - `:name` - The name to register the GenServer (default: __MODULE__)
  - `:table_name` - The ETS table name (default: :dspex_sessions)
  - `:cleanup_interval` - Cleanup interval in milliseconds (default: 60_000)
  - `:default_ttl` - Default TTL for sessions in seconds (default: 3600)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates a new session with the given ID and options.

  ## Parameters

  - `session_id` - Unique session identifier
  - `opts` - Keyword list of options passed to Session.new/2

  ## Returns

  `{:ok, session}` if successful, `{:error, reason}` if failed.

  ## Examples

      {:ok, session} = SessionStore.create_session("session_123")
      {:ok, session} = SessionStore.create_session("session_456", ttl: 7200)
  """
  @spec create_session(String.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def create_session(session_id, opts \\ []) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:create_session, session_id, opts})
  end

  @spec create_session(GenServer.server(), String.t(), keyword()) ::
          {:ok, Session.t()} | {:error, term()}
  def create_session(server, session_id, opts) when is_binary(session_id) do
    GenServer.call(server, {:create_session, session_id, opts})
  end

  @doc """
  Gets a session by ID, automatically updating the last_accessed timestamp.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  `{:ok, session}` if found, `{:error, :not_found}` if not found.
  """
  @spec get_session(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session(session_id) when is_binary(session_id) do
    get_session(__MODULE__, session_id)
  end

  @spec get_session(GenServer.server(), String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session(server, session_id) when is_binary(session_id) do
    GenServer.call(server, {:get_session, session_id})
  end

  @doc """
  Updates a session using the provided update function.

  The update function receives the current session and should return
  the updated session. The operation is atomic.

  ## Parameters

  - `session_id` - The session identifier
  - `update_fn` - Function that takes a session and returns an updated session

  ## Returns

  `{:ok, updated_session}` if successful, `{:error, reason}` if failed.

  ## Examples

      {:ok, session} = SessionStore.update_session("session_123", fn session ->
        Session.put_program(session, "prog_1", %{data: "example"})
      end)
  """
  @spec update_session(String.t(), (Session.t() -> Session.t())) ::
          {:ok, Session.t()} | {:error, term()}
  def update_session(session_id, update_fn)
      when is_binary(session_id) and is_function(update_fn, 1) do
    update_session(__MODULE__, session_id, update_fn)
  end

  @spec update_session(GenServer.server(), String.t(), (Session.t() -> Session.t())) ::
          {:ok, Session.t()} | {:error, term()}
  def update_session(server, session_id, update_fn)
      when is_binary(session_id) and is_function(update_fn, 1) do
    GenServer.call(server, {:update_session, session_id, update_fn})
  end

  @doc """
  Deletes a session by ID.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  `:ok` always (idempotent operation).
  """
  @spec delete_session(String.t()) :: :ok
  def delete_session(session_id) when is_binary(session_id) do
    delete_session(__MODULE__, session_id)
  end

  @spec delete_session(GenServer.server(), String.t()) :: :ok
  def delete_session(server, session_id) when is_binary(session_id) do
    GenServer.call(server, {:delete_session, session_id})
  end

  @doc """
  Manually triggers cleanup of expired sessions.

  ## Returns

  The number of sessions that were cleaned up.
  """
  @spec cleanup_expired_sessions() :: non_neg_integer()
  def cleanup_expired_sessions do
    cleanup_expired_sessions(__MODULE__)
  end

  @spec cleanup_expired_sessions(GenServer.server()) :: non_neg_integer()
  def cleanup_expired_sessions(server) do
    GenServer.call(server, :cleanup_expired_sessions)
  end

  @doc """
  Gets statistics about the session store.

  ## Returns

  A map containing various statistics about the session store.
  """
  @spec get_stats() :: map()
  def get_stats do
    get_stats(__MODULE__)
  end

  @spec get_stats(GenServer.server()) :: map()
  def get_stats(server) do
    GenServer.call(server, :get_stats)
  end

  @doc """
  Lists all active session IDs.

  ## Returns

  A list of all active session IDs.
  """
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    list_sessions(__MODULE__)
  end

  @spec list_sessions(GenServer.server()) :: [String.t()]
  def list_sessions(server) do
    GenServer.call(server, :list_sessions)
  end

  @doc """
  Checks if a session exists.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  `true` if the session exists, `false` otherwise.
  """
  @spec session_exists?(String.t()) :: boolean()
  def session_exists?(session_id) when is_binary(session_id) do
    session_exists?(__MODULE__, session_id)
  end

  @spec session_exists?(GenServer.server(), String.t()) :: boolean()
  def session_exists?(server, session_id) when is_binary(session_id) do
    GenServer.call(server, {:session_exists, session_id})
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Get table name from options or use default
    table_name = Keyword.get(opts, :table_name, @default_table_name)

    # Create ETS table with optimized concurrency settings
    table =
      :ets.new(table_name, [
        :set,
        :public,
        :named_table,
        {:read_concurrency, true},
        {:write_concurrency, true},
        {:decentralized_counters, true}
      ])

    cleanup_interval = Keyword.get(opts, :cleanup_interval, @cleanup_interval)
    default_ttl = Keyword.get(opts, :default_ttl, @default_ttl)

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_expired_sessions, cleanup_interval)

    state = %{
      table: table,
      table_name: table_name,
      cleanup_interval: cleanup_interval,
      default_ttl: default_ttl,
      stats: %{
        sessions_created: 0,
        sessions_deleted: 0,
        sessions_expired: 0,
        cleanup_runs: 0
      }
    }

    Logger.info("SessionStore started with table #{table}")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_session, session_id, opts}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, _existing_session}] ->
        {:reply, {:error, :already_exists}, state}

      [] ->
        # Set default TTL if not provided
        opts = Keyword.put_new(opts, :ttl, state.default_ttl)
        session = Session.new(session_id, opts)

        case Session.validate(session) do
          :ok ->
            :ets.insert(state.table, {session_id, session})
            new_stats = Map.update(state.stats, :sessions_created, 1, &(&1 + 1))
            {:reply, {:ok, session}, %{state | stats: new_stats}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:update_session, session_id, update_fn}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session}] ->
        try do
          updated_session = update_fn.(session)

          case Session.validate(updated_session) do
            :ok ->
              # Touch the session to update last_accessed
              touched_session = Session.touch(updated_session)
              :ets.insert(state.table, {session_id, touched_session})
              {:reply, {:ok, touched_session}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        rescue
          error ->
            Logger.error("Error updating session #{session_id}: #{inspect(error)}")
            {:reply, {:error, {:update_failed, error}}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:cleanup_expired_sessions, _from, state) do
    {expired_count, new_stats} = do_cleanup_expired_sessions(state.table, state.stats)
    {:reply, expired_count, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    current_sessions = :ets.info(state.table, :size)
    memory_usage = :ets.info(state.table, :memory) * :erlang.system_info(:wordsize)

    stats =
      Map.merge(state.stats, %{
        current_sessions: current_sessions,
        memory_usage_bytes: memory_usage,
        table_info: :ets.info(state.table)
      })

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_session, session_id}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, session}] ->
        # Touch the session to update last_accessed
        touched_session = Session.touch(session)
        :ets.insert(state.table, {session_id, touched_session})
        {:reply, {:ok, touched_session}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete_session, session_id}, _from, state) do
    :ets.delete(state.table, session_id)
    new_stats = Map.update(state.stats, :sessions_deleted, 1, &(&1 + 1))
    {:reply, :ok, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    session_ids = :ets.select(state.table, [{{:"$1", :_}, [], [:"$1"]}])
    {:reply, session_ids, state}
  end

  @impl true
  def handle_call({:session_exists, session_id}, _from, state) do
    exists =
      case :ets.lookup(state.table, session_id) do
        [{^session_id, _}] -> true
        [] -> false
      end

    {:reply, exists, state}
  end

  @impl true
  def handle_info(:cleanup_expired_sessions, state) do
    {_expired_count, new_stats} = do_cleanup_expired_sessions(state.table, state.stats)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired_sessions, state.cleanup_interval)

    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("SessionStore received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp do_cleanup_expired_sessions(table, stats) do
    current_time = System.monotonic_time(:second)

    # Instead of using complex ETS match specs, let's use a simpler approach
    # Get all sessions and filter expired ones manually for now
    all_sessions = :ets.tab2list(table)

    expired_sessions =
      Enum.filter(all_sessions, fn {_session_id, session} ->
        Session.expired?(session, current_time)
      end)

    # Delete expired sessions
    Enum.each(expired_sessions, fn {session_id, _session} ->
      :ets.delete(table, session_id)
    end)

    expired_count = length(expired_sessions)

    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired sessions")
    end

    new_stats =
      stats
      |> Map.update(:sessions_expired, expired_count, &(&1 + expired_count))
      |> Map.update(:cleanup_runs, 1, &(&1 + 1))

    {expired_count, new_stats}
  end
end
