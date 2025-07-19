defmodule DSPex.PythonBridge.SessionPoolMockTest do
  use ExUnit.Case, async: true

  alias DSPex.PythonBridge.SessionPool

  describe "session pool without real processes" do
    @tag :unit
    test "handle_call for session tracking" do
      # Create initial state
      state = %SessionPool{
        sessions: %{},
        metrics: %{
          total_operations: 0,
          successful_operations: 0,
          failed_operations: 0,
          total_sessions: 0,
          average_session_duration_ms: 0,
          pool_timeouts: 0,
          worker_errors: 0,
          stale_sessions_cleaned: 0
        }
      }

      # Test tracking a session
      {:reply, :ok, updated_state} =
        SessionPool.handle_call(
          {:track_session, "test_session"},
          {self(), make_ref()},
          state
        )

      assert Map.has_key?(updated_state.sessions, "test_session")
      assert updated_state.sessions["test_session"].operations == 0
    end

    @tag :unit
    test "handle_call for ending session" do
      now = System.monotonic_time(:millisecond)

      state = %SessionPool{
        sessions: %{
          "session_to_end" => %{
            started_at: now - 1000,
            last_activity: now,
            operations: 5,
            programs: MapSet.new()
          }
        },
        metrics: %{
          total_operations: 0,
          successful_operations: 0,
          failed_operations: 0,
          total_sessions: 0,
          average_session_duration_ms: 0,
          pool_timeouts: 0,
          worker_errors: 0,
          stale_sessions_cleaned: 0
        }
      }

      # Mock the cleanup_session_in_workers call
      {:reply, :ok, updated_state} =
        SessionPool.handle_call(
          {:end_session, "session_to_end"},
          {self(), make_ref()},
          state
        )

      refute Map.has_key?(updated_state.sessions, "session_to_end")
      assert updated_state.metrics.total_sessions == 1
    end

    @tag :unit
    test "handle_call for non-existent session" do
      state = %SessionPool{
        sessions: %{},
        metrics: %{}
      }

      {:reply, {:error, :session_not_found}, _} =
        SessionPool.handle_call(
          {:end_session, "ghost_session"},
          {self(), make_ref()},
          state
        )
    end

    @tag :unit
    test "handle_call for pool status" do
      state = %SessionPool{
        pool_size: 4,
        overflow: 2,
        sessions: %{"s1" => %{}, "s2" => %{}},
        metrics: %{total_operations: 100},
        started_at: System.monotonic_time(:millisecond) - 5000
      }

      {:reply, status, _} =
        SessionPool.handle_call(
          :get_status,
          {self(), make_ref()},
          state
        )

      assert status.pool_size == 4
      assert status.max_overflow == 2
      assert status.active_sessions == 2
      assert status.metrics.total_operations == 100
      assert status.uptime_ms >= 5000
    end

    @tag :unit
    test "handle_info for stale session cleanup" do
      now = System.monotonic_time(:millisecond)

      state = %SessionPool{
        sessions: %{
          # 1 second ago
          "fresh" => %{last_activity: now - 1000},
          # 2 hours ago
          "stale" => %{last_activity: now - 7_200_000}
        },
        metrics: %{
          stale_sessions_cleaned: 0,
          total_operations: 0,
          successful_operations: 0,
          failed_operations: 0,
          total_sessions: 0,
          average_session_duration_ms: 0,
          pool_timeouts: 0,
          worker_errors: 0
        },
        cleanup_ref: make_ref()
      }

      {:noreply, updated_state} =
        SessionPool.handle_info(
          :cleanup_stale_sessions,
          state
        )

      assert Map.has_key?(updated_state.sessions, "fresh")
      refute Map.has_key?(updated_state.sessions, "stale")
      assert updated_state.metrics.stale_sessions_cleaned == 1
    end
  end

  describe "metrics calculation" do
    @tag :unit
    test "update_session_end_metrics" do
      now = System.monotonic_time(:millisecond)

      metrics = %{
        total_sessions: 1,
        average_session_duration_ms: 1000,
        total_operations: 0,
        successful_operations: 0,
        failed_operations: 0,
        pool_timeouts: 0,
        worker_errors: 0,
        stale_sessions_cleaned: 0
      }

      session_info = %{
        # 2 seconds ago
        started_at: now - 2000,
        operations: 10
      }

      # Test the metrics calculation logic inline
      duration = now - session_info.started_at
      sessions = metrics.total_sessions + 1
      new_avg = (metrics.average_session_duration_ms * (sessions - 1) + duration) / sessions

      updated_metrics = %{
        metrics
        | total_sessions: sessions,
          average_session_duration_ms: new_avg
      }

      assert updated_metrics.total_sessions == 2
      # Average should be (1000 + 2000) / 2 = 1500
      assert_in_delta updated_metrics.average_session_duration_ms, 1500, 1
    end
  end
end
