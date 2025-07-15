defmodule DSPex.PythonBridge.SessionStoreTest do
  @moduledoc """
  Tests for the SessionStore GenServer.

  Uses basic isolation since we're testing a simple GenServer
  with proper unique naming and cleanup.
  """

  use DSPex.UnifiedTestFoundation, :basic

  alias DSPex.PythonBridge.{Session, SessionStore}

  setup %{test_id: test_id} do
    # Use test foundation's unique ID for consistent naming
    table_name = :"test_sessions_#{test_id}"
    store_name = :"test_store_#{test_id}"

    # Start a fresh SessionStore for each test with unique table
    {:ok, pid} =
      SessionStore.start_link(
        name: store_name,
        table_name: table_name,
        cleanup_interval: 100
      )

    # Use proper cleanup with graceful shutdown
    on_exit(fn ->
      graceful_supervisor_shutdown(pid, 5000)
    end)

    %{store_pid: pid, store_name: store_name, table_name: table_name}
  end

  describe "start_link/1" do
    test "starts with default options" do
      {:ok, pid} = SessionStore.start_link(name: :test_store_default)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "starts with custom options" do
      {:ok, pid} =
        SessionStore.start_link(
          name: :test_store_custom,
          cleanup_interval: 5000,
          default_ttl: 7200
        )

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "create_session/2" do
    test "creates a new session successfully", %{store_name: store_name} do
      assert {:ok, session} = SessionStore.create_session(store_name, "test_session_1", [])

      assert session.id == "test_session_1"
      assert session.programs == %{}
      assert session.metadata == %{}
      assert is_integer(session.created_at)
      assert is_integer(session.last_accessed)
      # default TTL
      assert session.ttl == 3600
    end

    test "creates session with custom options", %{store_name: store_name} do
      opts = [ttl: 7200, metadata: %{user_id: "user_123"}]

      assert {:ok, session} = SessionStore.create_session(store_name, "test_session_2", opts)

      assert session.id == "test_session_2"
      assert session.ttl == 7200
      assert session.metadata == %{user_id: "user_123"}
    end

    test "prevents duplicate session creation", %{store_name: store_name} do
      assert {:ok, _session} = SessionStore.create_session(store_name, "duplicate_session", [])

      assert {:error, :already_exists} =
               SessionStore.create_session(store_name, "duplicate_session", [])
    end

    test "validates session data", %{store_name: store_name} do
      # Test with invalid TTL
      assert {:error, :invalid_ttl} =
               SessionStore.create_session(store_name, "invalid_session", ttl: -1)
    end

    test "requires string session_id" do
      assert_raise FunctionClauseError, fn ->
        SessionStore.create_session(123)
      end
    end
  end

  describe "get_session/1" do
    test "retrieves existing session and updates last_accessed", %{store_name: store_name} do
      {:ok, original_session} = SessionStore.create_session(store_name, "get_test_session", [])
      original_time = original_session.last_accessed

      # Get session - this should update last_accessed automatically
      assert {:ok, retrieved_session} = SessionStore.get_session(store_name, "get_test_session")

      assert retrieved_session.id == "get_test_session"
      # The timestamp should be >= original (monotonic time can be equal if very fast)
      assert retrieved_session.last_accessed >= original_time
    end

    test "returns error for non-existent session", %{store_name: store_name} do
      assert {:error, :not_found} = SessionStore.get_session(store_name, "nonexistent_session")
    end

    test "requires string session_id" do
      assert_raise FunctionClauseError, fn ->
        SessionStore.get_session(123)
      end
    end
  end

  describe "update_session/2" do
    test "updates session successfully", %{store_name: store_name} do
      {:ok, _session} = SessionStore.create_session(store_name, "update_test_session", [])

      update_fn = fn session ->
        Session.put_program(session, "prog_1", %{data: "test_program"})
      end

      assert {:ok, updated_session} =
               SessionStore.update_session(store_name, "update_test_session", update_fn)

      assert updated_session.programs["prog_1"] == %{data: "test_program"}
    end

    test "updates last_accessed timestamp during update", %{store_name: store_name} do
      {:ok, original_session} =
        SessionStore.create_session(store_name, "update_timestamp_test", [])

      original_time = original_session.last_accessed

      update_fn = fn session ->
        Session.put_metadata(session, :updated, true)
      end

      assert {:ok, updated_session} =
               SessionStore.update_session(store_name, "update_timestamp_test", update_fn)

      # Update should automatically touch the session, updating last_accessed
      assert updated_session.last_accessed >= original_time
      assert updated_session.metadata[:updated] == true
    end

    test "returns error for non-existent session", %{store_name: store_name} do
      update_fn = fn session -> session end

      assert {:error, :not_found} =
               SessionStore.update_session(store_name, "nonexistent", update_fn)
    end

    test "validates updated session", %{store_name: store_name} do
      {:ok, _session} = SessionStore.create_session(store_name, "validation_test", [])

      # Update function that creates invalid session
      invalid_update_fn = fn _session ->
        %Session{
          # Invalid empty ID
          id: "",
          programs: %{},
          metadata: %{},
          created_at: System.monotonic_time(:second),
          last_accessed: System.monotonic_time(:second),
          ttl: 3600
        }
      end

      assert {:error, :invalid_id} =
               SessionStore.update_session(store_name, "validation_test", invalid_update_fn)
    end

    test "handles update function errors", %{store_name: store_name} do
      {:ok, _session} = SessionStore.create_session(store_name, "error_test", [])

      error_update_fn = fn _session ->
        raise "Update error"
      end

      assert {:error, {:update_failed, _}} =
               SessionStore.update_session(store_name, "error_test", error_update_fn)
    end

    test "requires function with arity 1", %{store_name: store_name} do
      {:ok, _session} = SessionStore.create_session(store_name, "arity_test", [])

      assert_raise FunctionClauseError, fn ->
        SessionStore.update_session(store_name, "arity_test", fn -> :invalid end)
      end
    end
  end

  describe "delete_session/1" do
    test "deletes existing session", %{store_name: store_name} do
      {:ok, _session} = SessionStore.create_session(store_name, "delete_test_session", [])

      assert :ok = SessionStore.delete_session(store_name, "delete_test_session")
      assert {:error, :not_found} = SessionStore.get_session(store_name, "delete_test_session")
    end

    test "is idempotent for non-existent sessions", %{store_name: store_name} do
      assert :ok = SessionStore.delete_session(store_name, "nonexistent_session")
    end

    test "requires string session_id" do
      assert_raise FunctionClauseError, fn ->
        SessionStore.delete_session(123)
      end
    end
  end

  describe "session_exists?/1" do
    test "returns true for existing session", %{store_name: store_name} do
      {:ok, _session} = SessionStore.create_session(store_name, "exists_test_session", [])

      assert SessionStore.session_exists?(store_name, "exists_test_session")
    end

    test "returns false for non-existent session", %{store_name: store_name} do
      refute SessionStore.session_exists?(store_name, "nonexistent_session")
    end

    test "requires string session_id" do
      assert_raise FunctionClauseError, fn ->
        SessionStore.session_exists?(123)
      end
    end
  end

  describe "list_sessions/0" do
    test "returns empty list when no sessions", %{store_name: store_name} do
      assert SessionStore.list_sessions(store_name) == []
    end

    test "returns list of session IDs", %{store_name: store_name} do
      {:ok, _} = SessionStore.create_session(store_name, "session_1", [])
      {:ok, _} = SessionStore.create_session(store_name, "session_2", [])
      {:ok, _} = SessionStore.create_session(store_name, "session_3", [])

      session_ids = SessionStore.list_sessions(store_name)

      assert length(session_ids) == 3
      assert "session_1" in session_ids
      assert "session_2" in session_ids
      assert "session_3" in session_ids
    end
  end

  describe "cleanup_expired_sessions/0" do
    test "removes expired sessions", %{store_name: store_name} do
      # Create session with very short TTL
      {:ok, session} = SessionStore.create_session(store_name, "short_ttl_session", ttl: 1)

      # Verify session exists
      assert SessionStore.session_exists?(store_name, "short_ttl_session")

      # Check that the session is not expired yet
      refute Session.expired?(session)

      # Use wait_for to wait for the session to be cleaned up
      result =
        wait_for(
          fn ->
            if SessionStore.session_exists?(store_name, "short_ttl_session") do
              # Still exists, keep waiting
              nil
            else
              # Session was cleaned up
              {:ok, :cleaned_up}
            end
          end,
          3000
        )

      assert {:ok, :cleaned_up} = result

      # Verify cleanup worked
      refute SessionStore.session_exists?(store_name, "short_ttl_session")
    end

    test "keeps non-expired sessions", %{store_name: store_name} do
      {:ok, _session} = SessionStore.create_session(store_name, "long_ttl_session", ttl: 3600)

      expired_count = SessionStore.cleanup_expired_sessions(store_name)

      assert expired_count == 0
      assert SessionStore.session_exists?(store_name, "long_ttl_session")
    end

    test "handles mixed expired and non-expired sessions", %{store_name: store_name} do
      {:ok, _} = SessionStore.create_session(store_name, "expired_1", ttl: 1)
      {:ok, _} = SessionStore.create_session(store_name, "expired_2", ttl: 1)
      {:ok, _} = SessionStore.create_session(store_name, "active_1", ttl: 3600)
      {:ok, _} = SessionStore.create_session(store_name, "active_2", ttl: 3600)

      # Use wait_for to wait for expired sessions to be cleaned up
      result =
        wait_for(
          fn ->
            expired_1_exists = SessionStore.session_exists?(store_name, "expired_1")
            expired_2_exists = SessionStore.session_exists?(store_name, "expired_2")

            if not expired_1_exists and not expired_2_exists do
              {:ok, :expired_sessions_cleaned}
            else
              # Keep waiting
              nil
            end
          end,
          3000
        )

      assert {:ok, :expired_sessions_cleaned} = result

      # Verify final state
      refute SessionStore.session_exists?(store_name, "expired_1")
      refute SessionStore.session_exists?(store_name, "expired_2")
      assert SessionStore.session_exists?(store_name, "active_1")
      assert SessionStore.session_exists?(store_name, "active_2")
    end
  end

  describe "get_stats/0" do
    test "returns comprehensive statistics", %{store_name: store_name} do
      {:ok, _} = SessionStore.create_session(store_name, "stats_session_1", [])
      {:ok, _} = SessionStore.create_session(store_name, "stats_session_2", [])

      stats = SessionStore.get_stats(store_name)

      assert is_map(stats)
      assert stats.current_sessions == 2
      assert stats.sessions_created == 2
      assert stats.sessions_deleted == 0
      assert stats.sessions_expired == 0
      assert stats.cleanup_runs >= 0
      assert is_integer(stats.memory_usage_bytes)
      assert is_list(stats.table_info)
    end

    test "tracks session operations in stats", %{store_name: store_name} do
      initial_stats = SessionStore.get_stats(store_name)

      {:ok, _} = SessionStore.create_session(store_name, "tracked_session", ttl: 1)
      SessionStore.delete_session(store_name, "tracked_session")

      # Trigger cleanup manually to update stats
      SessionStore.cleanup_expired_sessions(store_name)

      final_stats = SessionStore.get_stats(store_name)

      assert final_stats.sessions_created > initial_stats.sessions_created
      assert final_stats.sessions_deleted > initial_stats.sessions_deleted
      assert final_stats.cleanup_runs >= initial_stats.cleanup_runs
    end
  end

  describe "concurrent access" do
    test "handles concurrent session creation", %{store_name: store_name} do
      session_ids = for i <- 1..10, do: "concurrent_session_#{i}"

      tasks =
        Enum.map(session_ids, fn session_id ->
          Task.async(fn ->
            SessionStore.create_session(store_name, session_id, [])
          end)
        end)

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _session} -> true
               _ -> false
             end)

      # All sessions should exist
      assert Enum.all?(session_ids, &SessionStore.session_exists?(store_name, &1))
    end

    test "handles concurrent session updates", %{store_name: store_name} do
      {:ok, _} = SessionStore.create_session(store_name, "concurrent_update_session", [])

      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            SessionStore.update_session(store_name, "concurrent_update_session", fn session ->
              Session.put_program(session, "prog_#{i}", %{data: i})
            end)
          end)
        end

      results = Task.await_many(tasks)

      # All updates should succeed
      assert Enum.all?(results, fn
               {:ok, _session} -> true
               _ -> false
             end)

      # Final session should have all programs
      {:ok, final_session} = SessionStore.get_session(store_name, "concurrent_update_session")
      assert map_size(final_session.programs) == 5
    end

    test "handles concurrent read/write operations", %{store_name: store_name} do
      {:ok, _} = SessionStore.create_session(store_name, "concurrent_rw_session", [])

      # Mix of read and write operations
      tasks = [
        Task.async(fn -> SessionStore.get_session(store_name, "concurrent_rw_session") end),
        Task.async(fn ->
          SessionStore.update_session(store_name, "concurrent_rw_session", &Session.touch/1)
        end),
        Task.async(fn -> SessionStore.get_session(store_name, "concurrent_rw_session") end),
        Task.async(fn -> SessionStore.session_exists?(store_name, "concurrent_rw_session") end),
        Task.async(fn ->
          SessionStore.update_session(store_name, "concurrent_rw_session", &Session.touch/1)
        end)
      ]

      results = Task.await_many(tasks)

      # All operations should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               true -> true
               _ -> false
             end)
    end
  end

  describe "automatic cleanup" do
    test "performs periodic cleanup automatically", %{store_name: store_name} do
      # Create session with short TTL
      {:ok, _} = SessionStore.create_session(store_name, "auto_cleanup_session", ttl: 1)

      # Verify session exists
      assert SessionStore.session_exists?(store_name, "auto_cleanup_session")

      # Use wait_for to wait for automatic cleanup (cleanup_interval is 100ms in setup)
      result =
        wait_for(
          fn ->
            if SessionStore.session_exists?(store_name, "auto_cleanup_session") do
              # Still exists, keep waiting
              nil
            else
              # Session was automatically cleaned up
              {:ok, :auto_cleaned}
            end
          end,
          3000
        )

      assert {:ok, :auto_cleaned} = result

      # Session should be cleaned up automatically
      refute SessionStore.session_exists?(store_name, "auto_cleanup_session")
    end
  end

  describe "error handling" do
    test "handles ETS table errors gracefully", %{store_name: store_name} do
      # This test is more conceptual since we can't easily simulate ETS failures
      # in a controlled way, but the error handling is implemented in the code

      # Test with invalid session data that would cause ETS issues
      {:ok, _} = SessionStore.create_session(store_name, "error_handling_test", [])

      # The update should handle any internal errors
      result =
        SessionStore.update_session(store_name, "error_handling_test", fn _session ->
          # This should be caught and handled
          raise "Simulated error"
        end)

      assert {:error, {:update_failed, _}} = result
    end
  end

  describe "edge cases" do
    test "handles empty session ID validation", %{store_name: store_name} do
      # This is handled by Session.validate/1
      assert {:error, :invalid_id} = SessionStore.create_session(store_name, "", ttl: 3600)
    end

    test "handles very large TTL values", %{store_name: store_name} do
      large_ttl = 999_999_999

      assert {:ok, session} =
               SessionStore.create_session(store_name, "large_ttl_session", ttl: large_ttl)

      assert session.ttl == large_ttl
    end

    test "handles session with many programs", %{store_name: store_name} do
      {:ok, _} = SessionStore.create_session(store_name, "many_programs_session", [])

      # Add many programs
      update_fn = fn session ->
        Enum.reduce(1..100, session, fn i, acc ->
          Session.put_program(acc, "prog_#{i}", %{data: i})
        end)
      end

      assert {:ok, updated_session} =
               SessionStore.update_session(store_name, "many_programs_session", update_fn)

      assert map_size(updated_session.programs) == 100
    end
  end
end
