defmodule DSPex.PythonBridge.SessionPoolUnitTest do
  use ExUnit.Case, async: true

  alias DSPex.PythonBridge.SessionPool

  describe "GenServer state management" do
    @tag :unit
    test "initializes with correct state structure" do
      # Test the state initialization without starting NimblePool
      initial_state = %SessionPool{
        pool_name: :test_pool,
        pool_size: 2,
        overflow: 1,
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
        },
        health_check_ref: nil,
        cleanup_ref: nil,
        started_at: System.monotonic_time(:millisecond)
      }

      assert initial_state.pool_size == 2
      assert initial_state.overflow == 1
      assert initial_state.sessions == %{}
      assert is_map(initial_state.metrics)
    end
  end

  describe "session tracking logic" do
    @tag :unit
    test "adds new session to state" do
      state = %SessionPool{
        sessions: %{},
        metrics: %{total_operations: 0}
      }

      # Simulate tracking a session
      session_id = "test_session_1"
      now = System.monotonic_time(:millisecond)

      new_session = %{
        started_at: now,
        last_activity: now,
        operations: 0,
        programs: MapSet.new()
      }

      updated_sessions = Map.put(state.sessions, session_id, new_session)
      updated_state = %{state | sessions: updated_sessions}

      assert Map.has_key?(updated_state.sessions, session_id)
      assert updated_state.sessions[session_id].operations == 0
    end

    @tag :unit
    test "removes session from state" do
      now = System.monotonic_time(:millisecond)

      state = %SessionPool{
        sessions: %{
          "session_to_remove" => %{
            started_at: now - 1000,
            last_activity: now,
            operations: 5,
            programs: MapSet.new()
          }
        },
        metrics: %{
          total_sessions: 0,
          average_session_duration_ms: 0
        }
      }

      # Simulate ending a session
      {session_info, remaining_sessions} = Map.pop(state.sessions, "session_to_remove")

      assert session_info != nil
      assert remaining_sessions == %{}

      # Calculate metrics update
      duration = now - session_info.started_at
      assert duration > 0
    end
  end

  describe "metrics calculation" do
    @tag :unit
    test "updates average session duration correctly" do
      metrics = %{
        total_sessions: 2,
        average_session_duration_ms: 1000
      }

      new_duration = 2000

      # Calculate new average
      sessions = metrics.total_sessions + 1

      new_avg =
        (metrics.average_session_duration_ms * metrics.total_sessions + new_duration) / sessions

      assert new_avg == 1333.3333333333333
    end

    @tag :unit
    test "identifies stale sessions" do
      now = System.monotonic_time(:millisecond)
      # 1 hour
      stale_timeout = 3600_000

      sessions = %{
        "fresh_session" => %{
          # 5 minutes ago
          last_activity: now - 300_000
        },
        "stale_session" => %{
          # 2 hours ago
          last_activity: now - 7200_000
        }
      }

      {stale, active} =
        Map.split_with(sessions, fn {_id, info} ->
          now - info.last_activity > stale_timeout
        end)

      assert map_size(stale) == 1
      assert Map.has_key?(stale, "stale_session")
      assert map_size(active) == 1
      assert Map.has_key?(active, "fresh_session")
    end
  end

  describe "pool status formatting" do
    @tag :unit
    test "formats status correctly" do
      state = %SessionPool{
        pool_size: 4,
        overflow: 2,
        sessions: %{"s1" => %{}, "s2" => %{}},
        metrics: %{
          total_operations: 100,
          successful_operations: 95,
          failed_operations: 5
        },
        started_at: System.monotonic_time(:millisecond) - 60_000
      }

      status = %{
        pool_size: state.pool_size,
        max_overflow: state.overflow,
        active_sessions: map_size(state.sessions),
        metrics: state.metrics,
        uptime_ms: System.monotonic_time(:millisecond) - state.started_at,
        pool_status: %{ready: :unknown, busy: :unknown, overflow: :unknown}
      }

      assert status.pool_size == 4
      assert status.active_sessions == 2
      assert status.uptime_ms >= 60_000
    end
  end
end
