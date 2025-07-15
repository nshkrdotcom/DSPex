defmodule DSPex.PythonBridge.SessionMigratorTest do
  use ExUnit.Case, async: true

  alias DSPex.PythonBridge.{SessionMigrator, SessionStore, Session}

  setup do
    # Generate unique names to avoid conflicts
    store_name = :"test_session_store_#{System.unique_integer()}"
    migrator_name = :"test_session_migrator_#{System.unique_integer()}"
    migration_table = :"test_migrations_#{System.unique_integer()}"

    # Start SessionStore for testing
    {:ok, store_pid} = SessionStore.start_link(name: store_name)

    # Start SessionMigrator for testing
    {:ok, migrator_pid} =
      SessionMigrator.start_link(
        name: migrator_name,
        migration_table: migration_table,
        cleanup_interval: 1000,
        session_store: store_name
      )

    # Create a test session
    session_id = "test_session_#{System.unique_integer()}"
    {:ok, _session} = SessionStore.create_session(store_name, session_id, [])

    on_exit(fn ->
      if Process.alive?(store_pid), do: GenServer.stop(store_pid)
      if Process.alive?(migrator_pid), do: GenServer.stop(migrator_pid)
    end)

    %{
      session_id: session_id,
      store_pid: store_pid,
      migrator_pid: migrator_pid,
      store_name: store_name,
      migrator_name: migrator_name
    }
  end

  describe "migrate_session/3" do
    test "successfully migrates a session", %{
      session_id: session_id,
      migrator_name: migrator_name
    } do
      # Migrate session from worker1 to worker2
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      assert is_binary(migration_id)
      assert String.starts_with?(migration_id, "migration_")

      # Wait for migration to complete
      :timer.sleep(300)

      # Check migration status
      {:ok, migration_state} = SessionMigrator.get_migration_status(migrator_name, migration_id)
      assert migration_state.status == :completed
      assert migration_state.session_id == session_id
      assert migration_state.from_worker == "worker1"
      assert migration_state.to_worker == "worker2"
    end

    test "fails to migrate non-existent session", %{migrator_name: migrator_name} do
      # Migration will start but fail during execution
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          "non_existent_session",
          "worker1",
          "worker2"
        )

      # Wait for migration to fail
      :timer.sleep(200)

      # Check migration failed
      {:ok, migration_state} = SessionMigrator.get_migration_status(migrator_name, migration_id)
      assert migration_state.status == :failed
      assert migration_state.error == :session_not_found
    end

    test "fails to migrate to same worker", %{migrator_name: migrator_name} do
      {:error, :same_worker} =
        SessionMigrator.migrate_session(
          migrator_name,
          "any_session",
          "worker1",
          "worker1"
        )
    end

    test "fails with invalid session_id", %{migrator_name: migrator_name} do
      {:error, :invalid_session_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          "",
          "worker1",
          "worker2"
        )
    end
  end

  describe "get_migration_status/2" do
    test "returns migration status for existing migration", %{
      session_id: session_id,
      migrator_name: migrator_name
    } do
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      {:ok, migration_state} = SessionMigrator.get_migration_status(migrator_name, migration_id)
      assert migration_state.migration_id == migration_id
      assert migration_state.session_id == session_id
      assert migration_state.status in [:pending, :in_progress, :completed]
    end

    test "returns not_found for non-existent migration", %{migrator_name: migrator_name} do
      {:error, :not_found} =
        SessionMigrator.get_migration_status(
          migrator_name,
          "non_existent_migration"
        )
    end
  end

  describe "list_active_migrations/1" do
    test "lists active migrations", %{session_id: session_id, migrator_name: migrator_name} do
      # Start a migration
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      active_migrations = SessionMigrator.list_active_migrations(migrator_name)

      # Should contain our migration (might be pending, in_progress, or completed)
      migration_ids = Enum.map(active_migrations, & &1.migration_id)
      assert migration_id in migration_ids
    end

    test "returns empty list when no active migrations", %{migrator_name: migrator_name} do
      active_migrations = SessionMigrator.list_active_migrations(migrator_name)
      assert is_list(active_migrations)
    end
  end

  describe "rollback_migration/2" do
    test "successfully rolls back completed migration", %{
      session_id: session_id,
      migrator_name: migrator_name
    } do
      # Start and complete a migration
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      # Wait for migration to complete
      :timer.sleep(200)

      # Verify migration is completed
      {:ok, migration_state} = SessionMigrator.get_migration_status(migrator_name, migration_id)
      assert migration_state.status == :completed

      # Rollback the migration
      :ok = SessionMigrator.rollback_migration(migrator_name, migration_id)

      # Verify rollback status
      {:ok, rolled_back_state} = SessionMigrator.get_migration_status(migrator_name, migration_id)
      assert rolled_back_state.status == :rolled_back
    end

    test "fails to rollback non-existent migration", %{migrator_name: migrator_name} do
      {:error, :not_found} =
        SessionMigrator.rollback_migration(
          migrator_name,
          "non_existent_migration"
        )
    end
  end

  describe "cancel_migration/2" do
    test "successfully cancels pending migration", %{
      session_id: session_id,
      migrator_name: migrator_name
    } do
      # Start a migration
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      # Cancel immediately (should be pending or in_progress)
      :ok = SessionMigrator.cancel_migration(migrator_name, migration_id)

      # Verify cancellation
      {:ok, migration_state} = SessionMigrator.get_migration_status(migrator_name, migration_id)
      assert migration_state.status == :failed
      assert migration_state.error == :cancelled
    end

    test "fails to cancel non-existent migration", %{migrator_name: migrator_name} do
      {:error, :not_found} =
        SessionMigrator.cancel_migration(
          migrator_name,
          "non_existent_migration"
        )
    end
  end

  describe "get_migration_stats/1" do
    test "returns migration statistics", %{migrator_name: migrator_name} do
      stats = SessionMigrator.get_migration_stats(migrator_name)

      assert is_map(stats)
      assert Map.has_key?(stats, :migrations_started)
      assert Map.has_key?(stats, :migrations_completed)
      assert Map.has_key?(stats, :migrations_failed)
      assert Map.has_key?(stats, :migrations_rolled_back)
      assert Map.has_key?(stats, :total_migrations)
      assert Map.has_key?(stats, :active_migrations)
    end
  end

  describe "session metadata tracking" do
    test "migration updates session metadata", %{
      session_id: session_id,
      migrator_name: migrator_name,
      store_name: store_name
    } do
      # Start migration
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      # Wait for migration to complete
      :timer.sleep(200)

      # Check that session metadata was updated
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      last_migration = Session.get_metadata(session, :last_migration)

      assert is_map(last_migration)
      assert last_migration.migration_id == migration_id
      assert last_migration.from_worker == "worker1"
      assert last_migration.to_worker == "worker2"
      assert is_integer(last_migration.migrated_at)
    end

    test "rollback removes migration metadata", %{
      session_id: session_id,
      migrator_name: migrator_name,
      store_name: store_name
    } do
      # Start and complete migration
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      # Wait for migration to complete
      :timer.sleep(200)

      # Rollback migration
      :ok = SessionMigrator.rollback_migration(migrator_name, migration_id)

      # Check that migration metadata was removed
      {:ok, session} = SessionStore.get_session(store_name, session_id)
      last_migration = Session.get_metadata(session, :last_migration)

      assert is_nil(last_migration)
    end
  end

  describe "error handling" do
    test "handles session store errors gracefully", %{
      session_id: session_id,
      migrator_name: migrator_name,
      store_pid: store_pid
    } do
      # Stop the session store to simulate failure
      GenServer.stop(store_pid)

      # Try to migrate - should handle the error
      {:ok, migration_id} =
        SessionMigrator.migrate_session(
          migrator_name,
          session_id,
          "worker1",
          "worker2"
        )

      # Wait for migration to fail
      :timer.sleep(200)

      # Check migration failed
      {:ok, migration_state} = SessionMigrator.get_migration_status(migrator_name, migration_id)
      assert migration_state.status == :failed
      assert is_tuple(migration_state.error)
    end
  end
end
