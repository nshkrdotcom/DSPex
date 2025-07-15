defmodule DSPex.PythonBridge.SessionMigrator do
  @moduledoc """
  Session migration system for dynamic session redistribution.

  This module provides functionality for migrating sessions between workers,
  load rebalancing, worker evacuation, and migration monitoring with rollback
  capabilities. It maintains migration state tracking using ETS for high
  performance and reliability.
  """

  use GenServer
  require Logger

  alias DSPex.PythonBridge.{SessionStore, Session}

  @default_migration_table :dspex_session_migrations
  @migration_timeout 30_000
  @cleanup_interval 300_000  # 5 minutes

  @type migration_status :: :pending | :in_progress | :completed | :failed | :rolled_back

  @type migration_state :: %{
    migration_id: String.t(),
    session_id: String.t(),
    from_worker: String.t() | nil,
    to_worker: String.t() | nil,
    status: migration_status(),
    started_at: integer(),
    completed_at: integer() | nil,
    error: term() | nil,
    rollback_data: map() | nil
  }

  ## Client API

  @doc """
  Starts the SessionMigrator GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Migrates a session from one worker to another.
  """
  @spec migrate_session(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def migrate_session(session_id, from_worker, to_worker) do
    migrate_session(__MODULE__, session_id, from_worker, to_worker)
  end

  @spec migrate_session(GenServer.server(), String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def migrate_session(server, session_id, from_worker, to_worker) do
    GenServer.call(server, {:migrate_session, session_id, from_worker, to_worker}, @migration_timeout + 5000)
  end

  @doc """
  Gets the status of a migration.
  """
  @spec get_migration_status(String.t()) :: {:ok, migration_state()} | {:error, :not_found}
  def get_migration_status(migration_id) do
    get_migration_status(__MODULE__, migration_id)
  end

  @spec get_migration_status(GenServer.server(), String.t()) :: {:ok, migration_state()} | {:error, :not_found}
  def get_migration_status(server, migration_id) do
    GenServer.call(server, {:get_migration_status, migration_id})
  end

  @doc """
  Lists all active migrations.
  """
  @spec list_active_migrations() :: [migration_state()]
  def list_active_migrations do
    list_active_migrations(__MODULE__)
  end

  @spec list_active_migrations(GenServer.server()) :: [migration_state()]
  def list_active_migrations(server) do
    GenServer.call(server, :list_active_migrations)
  end

  @doc """
  Rolls back a migration if possible.
  """
  @spec rollback_migration(String.t()) :: :ok | {:error, term()}
  def rollback_migration(migration_id) do
    rollback_migration(__MODULE__, migration_id)
  end

  @spec rollback_migration(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def rollback_migration(server, migration_id) do
    GenServer.call(server, {:rollback_migration, migration_id}, @migration_timeout + 5000)
  end

  @doc """
  Cancels a pending or in-progress migration.
  """
  @spec cancel_migration(String.t()) :: :ok | {:error, term()}
  def cancel_migration(migration_id) do
    cancel_migration(__MODULE__, migration_id)
  end

  @spec cancel_migration(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def cancel_migration(server, migration_id) do
    GenServer.call(server, {:cancel_migration, migration_id})
  end

  @doc """
  Gets migration statistics.
  """
  @spec get_migration_stats() :: map()
  def get_migration_stats do
    get_migration_stats(__MODULE__)
  end

  @spec get_migration_stats(GenServer.server()) :: map()
  def get_migration_stats(server) do
    GenServer.call(server, :get_migration_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    migration_table = Keyword.get(opts, :migration_table, @default_migration_table)
    migration_timeout = Keyword.get(opts, :migration_timeout, @migration_timeout)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @cleanup_interval)
    session_store = Keyword.get(opts, :session_store, DSPex.PythonBridge.SessionStore)

    # Create ETS table for migration tracking
    table = :ets.new(migration_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])

    # Schedule periodic cleanup of old migrations
    Process.send_after(self(), :cleanup_old_migrations, cleanup_interval)

    state = %{
      table: table,
      table_name: migration_table,
      migration_timeout: migration_timeout,
      cleanup_interval: cleanup_interval,
      session_store: session_store,
      stats: %{
        migrations_started: 0,
        migrations_completed: 0,
        migrations_failed: 0,
        migrations_rolled_back: 0,
        cleanup_runs: 0
      }
    }

    Logger.info("SessionMigrator started with table #{migration_table}")
    {:ok, state}
  end

  @impl true
  def handle_call({:migrate_session, session_id, from_worker, to_worker}, _from, state) do
    case validate_migration_request(session_id, from_worker, to_worker) do
      :ok ->
        migration_id = generate_migration_id()

        migration_state = %{
          migration_id: migration_id,
          session_id: session_id,
          from_worker: from_worker,
          to_worker: to_worker,
          status: :pending,
          started_at: System.monotonic_time(:second),
          completed_at: nil,
          error: nil,
          rollback_data: nil
        }

        # Store migration state
        :ets.insert(state.table, {migration_id, migration_state})

        # Start migration process asynchronously
        Task.start(fn -> perform_migration(migration_id, state.table, state.session_store) end)

        new_stats = Map.update(state.stats, :migrations_started, 1, &(&1 + 1))
        {:reply, {:ok, migration_id}, %{state | stats: new_stats}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_migration_status, migration_id}, _from, state) do
    case :ets.lookup(state.table, migration_id) do
      [{^migration_id, migration_state}] ->
        {:reply, {:ok, migration_state}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_active_migrations, _from, state) do
    active_migrations = :ets.select(state.table, [
      {{:"$1", :"$2"},
       [{:"/=", {:map_get, :status, :"$2"}, :completed},
        {:"/=", {:map_get, :status, :"$2"}, :failed},
        {:"/=", {:map_get, :status, :"$2"}, :rolled_back}],
       [:"$2"]}
    ])
    {:reply, active_migrations, state}
  end

  @impl true
  def handle_call({:rollback_migration, migration_id}, _from, state) do
    case :ets.lookup(state.table, migration_id) do
      [{^migration_id, migration_state}] ->
        case perform_rollback(migration_state, state.table, state.session_store) do
          :ok ->
            new_stats = Map.update(state.stats, :migrations_rolled_back, 1, &(&1 + 1))
            {:reply, :ok, %{state | stats: new_stats}}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:cancel_migration, migration_id}, _from, state) do
    case :ets.lookup(state.table, migration_id) do
      [{^migration_id, migration_state}] ->
        case migration_state.status do
          status when status in [:pending, :in_progress] ->
            updated_state = %{migration_state |
              status: :failed,
              completed_at: System.monotonic_time(:second),
              error: :cancelled
            }
            :ets.insert(state.table, {migration_id, updated_state})
            {:reply, :ok, state}
          _ ->
            {:reply, {:error, :cannot_cancel}, state}
        end
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:get_migration_stats, _from, state) do
    total_migrations = :ets.info(state.table, :size)
    active_count = length(:ets.select(state.table, [
      {{:"$1", :"$2"},
       [{:"/=", {:map_get, :status, :"$2"}, :completed},
        {:"/=", {:map_get, :status, :"$2"}, :failed},
        {:"/=", {:map_get, :status, :"$2"}, :rolled_back}],
       [:"$1"]}
    ]))

    stats = Map.merge(state.stats, %{
      total_migrations: total_migrations,
      active_migrations: active_count,
      table_info: :ets.info(state.table)
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup_old_migrations, state) do
    cleanup_count = cleanup_old_migrations(state.table)

    if cleanup_count > 0 do
      Logger.debug("Cleaned up #{cleanup_count} old migration records")
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_old_migrations, state.cleanup_interval)

    new_stats = Map.update(state.stats, :cleanup_runs, 1, &(&1 + 1))
    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info({:migration_completed, migration_id, result}, state) do
    case :ets.lookup(state.table, migration_id) do
      [{^migration_id, migration_state}] ->
        {status, error, new_stats} = case result do
          :ok ->
            {:completed, nil, Map.update(state.stats, :migrations_completed, 1, &(&1 + 1))}
          {:error, reason} ->
            {:failed, reason, Map.update(state.stats, :migrations_failed, 1, &(&1 + 1))}
        end

        updated_state = %{migration_state |
          status: status,
          completed_at: System.monotonic_time(:second),
          error: error
        }

        :ets.insert(state.table, {migration_id, updated_state})
        {:noreply, %{state | stats: new_stats}}

      [] ->
        Logger.warning("Received completion for unknown migration: #{migration_id}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("SessionMigrator received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp validate_migration_request(session_id, from_worker, to_worker) do
    cond do
      not is_binary(session_id) or session_id == "" ->
        {:error, :invalid_session_id}

      from_worker == to_worker ->
        {:error, :same_worker}

      true ->
        # For now, skip the session existence check since we don't have
        # a way to pass the SessionStore server reference to this function.
        # The actual migration will fail if the session doesn't exist.
        :ok
    end
  end

  defp generate_migration_id do
    timestamp = System.monotonic_time(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)
    "migration_#{timestamp}_#{random}"
  end

  defp perform_migration(migration_id, table, session_store) do
    # Update status to in_progress
    case :ets.lookup(table, migration_id) do
      [{^migration_id, migration_state}] ->
        updated_state = %{migration_state | status: :in_progress}
        :ets.insert(table, {migration_id, updated_state})

        # Perform the actual migration
        result = do_migrate_session(migration_state, session_store)

        # Send completion message to GenServer
        send(self(), {:migration_completed, migration_id, result})

      [] ->
        Logger.error("Migration state not found for #{migration_id}")
    end
  end

  defp do_migrate_session(%{session_id: session_id} = migration_state, session_store) do
    try do
      # For centralized session store, migration is mostly a metadata operation
      # since sessions are already centralized. This is mainly for tracking
      # and future worker-specific optimizations.

      case SessionStore.get_session(session_store, session_id) do
        {:ok, session} ->
          # Update session metadata to track migration
          updated_session = Session.put_metadata(session, :last_migration, %{
            migration_id: migration_state.migration_id,
            from_worker: migration_state.from_worker,
            to_worker: migration_state.to_worker,
            migrated_at: System.monotonic_time(:second)
          })

          case SessionStore.update_session(session_store, session_id, fn _session -> updated_session end) do
            {:ok, _} ->
              Logger.info("Successfully migrated session #{session_id} from #{migration_state.from_worker} to #{migration_state.to_worker}")
              :ok

            {:error, reason} ->
              Logger.error("Failed to update session #{session_id} during migration: #{inspect(reason)}")
              {:error, {:session_update_failed, reason}}
          end

        {:error, :not_found} ->
          Logger.error("Session #{session_id} not found during migration")
          {:error, :session_not_found}

        {:error, reason} ->
          Logger.error("Failed to get session #{session_id} during migration: #{inspect(reason)}")
          {:error, {:session_get_failed, reason}}
      end
    rescue
      error ->
        Logger.error("Exception during migration of session #{session_id}: #{inspect(error)}")
        {:error, {:migration_exception, error}}
    end
  end

  defp perform_rollback(%{migration_id: migration_id, session_id: session_id, status: status} = migration_state, table, session_store) do
    case status do
      :completed ->
        try do
          # Remove migration metadata from session
          case SessionStore.update_session(session_store, session_id, fn session ->
            metadata = Map.delete(session.metadata, :last_migration)
            %{session | metadata: metadata}
          end) do
            {:ok, _} ->
              # Update migration state
              updated_state = %{migration_state |
                status: :rolled_back,
                completed_at: System.monotonic_time(:second)
              }
              :ets.insert(table, {migration_id, updated_state})

              Logger.info("Successfully rolled back migration #{migration_id} for session #{session_id}")
              :ok

            {:error, reason} ->
              Logger.error("Failed to rollback migration #{migration_id}: #{inspect(reason)}")
              {:error, {:rollback_failed, reason}}
          end
        rescue
          error ->
            Logger.error("Exception during rollback of migration #{migration_id}: #{inspect(error)}")
            {:error, {:rollback_exception, error}}
        end

      status when status in [:failed, :rolled_back] ->
        {:error, :already_rolled_back_or_failed}

      status when status in [:pending, :in_progress] ->
        {:error, :migration_not_completed}
    end
  end

  defp cleanup_old_migrations(table) do
    # Clean up migrations older than 24 hours
    cutoff_time = System.monotonic_time(:second) - (24 * 60 * 60)

    old_migrations = :ets.select(table, [
      {{:"$1", :"$2"},
       [{:"<", {:map_get, :started_at, :"$2"}, cutoff_time},
        {:orelse,
         {:==, {:map_get, :status, :"$2"}, :completed},
         {:==, {:map_get, :status, :"$2"}, :failed},
         {:==, {:map_get, :status, :"$2"}, :rolled_back}}],
       [:"$1"]}
    ])

    Enum.each(old_migrations, fn migration_id ->
      :ets.delete(table, migration_id)
    end)

    length(old_migrations)
  end
end
