defmodule DSPex.PythonBridge.SessionPoolTest do
  use ExUnit.Case
  alias DSPex.PythonBridge.SessionPool

  # These tests require real NimblePool and Python processes - Layer 3 only
  @moduletag :layer_3

  describe "session management" do
    setup do
      # Start a test pool with minimal configuration
      start_supervised!({SessionPool, name: :test_session_pool, pool_size: 2})
      :ok
    end

    @tag :unit
    test "tracks new sessions" do
      assert :ok = GenServer.call(:test_session_pool, {:track_session, "session_1"})
      assert :ok = GenServer.call(:test_session_pool, {:track_session, "session_2"})

      sessions = GenServer.call(:test_session_pool, :get_sessions)
      assert map_size(sessions) == 2
      assert Map.has_key?(sessions, "session_1")
      assert Map.has_key?(sessions, "session_2")
    end

    @tag :unit
    test "prevents duplicate session tracking" do
      assert :ok = GenServer.call(:test_session_pool, {:track_session, "dup_session"})
      assert :ok = GenServer.call(:test_session_pool, {:track_session, "dup_session"})

      sessions = GenServer.call(:test_session_pool, :get_sessions)
      # Should still only have one entry
      assert length(Map.keys(sessions)) == 1
    end

    @tag :unit
    test "ends sessions successfully" do
      GenServer.call(:test_session_pool, {:track_session, "temp_session"})
      assert :ok = GenServer.call(:test_session_pool, {:end_session, "temp_session"})

      sessions = GenServer.call(:test_session_pool, :get_sessions)
      refute Map.has_key?(sessions, "temp_session")
    end

    @tag :unit
    test "handles ending non-existent session" do
      assert {:error, :session_not_found} =
               GenServer.call(:test_session_pool, {:end_session, "ghost_session"})
    end
  end

  describe "pool status and metrics" do
    setup do
      start_supervised!({SessionPool, name: :metrics_pool, pool_size: 3})
      :ok
    end

    @tag :unit
    test "returns pool status with metrics" do
      status = GenServer.call(:metrics_pool, :get_status)

      assert status.pool_size == 3
      assert status.active_sessions == 0
      assert is_map(status.metrics)
      assert status.metrics.total_operations == 0
      assert status.uptime_ms >= 0
    end

    @tag :unit
    test "tracks session metrics" do
      # Create and track a session
      GenServer.call(:metrics_pool, {:track_session, "metric_session"})

      # Get initial status
      status1 = GenServer.call(:metrics_pool, :get_status)
      assert status1.active_sessions == 1

      # End session
      GenServer.call(:metrics_pool, {:end_session, "metric_session"})

      # Check updated metrics
      status2 = GenServer.call(:metrics_pool, :get_status)
      assert status2.active_sessions == 0
      assert status2.metrics.total_sessions == 1
    end
  end

  describe "health check functionality" do
    setup do
      start_supervised!({SessionPool, name: :health_pool, pool_size: 2})
      :ok
    end

    @tag :unit
    test "performs health check" do
      health_results = GenServer.call(:health_pool, :health_check, 10_000)

      assert is_map(health_results)
      assert Map.has_key?(health_results, :healthy_workers)
      assert Map.has_key?(health_results, :total_workers)
    end
  end

  describe "graceful shutdown" do
    @tag :unit
    test "shuts down pool gracefully" do
      {:ok, pool} = SessionPool.start_link(name: :shutdown_pool, pool_size: 1)

      # Track some sessions
      GenServer.call(:shutdown_pool, {:track_session, "shutdown_session"})

      # Shutdown should complete
      assert :ok = GenServer.call(:shutdown_pool, :shutdown, 5_000)

      # Pool should no longer be alive
      Process.sleep(100)
      refute Process.alive?(pool)
    end
  end

  describe "stale session cleanup" do
    @tag :unit
    test "cleans up stale sessions" do
      start_supervised!({SessionPool, name: :cleanup_pool, pool_size: 1})

      # Simulate adding a stale session by manipulating state directly
      # In real tests, we'd wait for the timeout or mock the time
      _state = :sys.get_state(:cleanup_pool)

      # Add a session with old timestamp
      old_session = %{
        # 2 hours ago
        started_at: System.monotonic_time(:millisecond) - 7_200_000,
        last_activity: System.monotonic_time(:millisecond) - 7_200_000,
        operations: 0,
        programs: MapSet.new()
      }

      :sys.replace_state(:cleanup_pool, fn state ->
        %{state | sessions: Map.put(state.sessions, "stale_session", old_session)}
      end)

      # Trigger cleanup
      send(:cleanup_pool, :cleanup_stale_sessions)
      Process.sleep(100)

      # Check session was removed
      sessions = GenServer.call(:cleanup_pool, :get_sessions)
      refute Map.has_key?(sessions, "stale_session")
    end
  end
end
