defmodule DSPex.PythonBridge.PoolWorkerTest do
  use ExUnit.Case, async: true
  alias DSPex.PythonBridge.PoolWorker
  import DSPex.Test.PoolWorkerHelpers

  # These tests require actual Port operations and should run in Layer 3
  @moduletag :layer_3

  describe "init_worker/1" do
    @tag :layer_3
    test "initializes worker with correct state structure" do
      pool_state = %{worker_id: "test_worker_1"}

      # This test requires actual Python environment
      case PoolWorker.init_worker(pool_state) do
        {:ok, worker_state, _updated_pool} ->
          assert worker_state.worker_id != nil
          assert worker_state.health_status in [:healthy, :initializing]
          assert worker_state.current_session == nil
          # Incremented by initialization ping
          assert worker_state.request_id == 1
          assert is_map(worker_state.stats)

          # Clean up
          PoolWorker.terminate_worker(:shutdown, worker_state, pool_state)

        {:error, reason} ->
          # Python environment might not be available
          IO.puts("Skipping init_worker test: #{inspect(reason)}")
      end
    end
  end

  describe "handle_checkout/4" do
    setup do
      # Create a complete worker state struct
      worker_state = %DSPex.PythonBridge.PoolWorker{
        # Mock port as current process
        port: self(),
        python_path: "/usr/bin/python3",
        script_path: "test/script.py",
        worker_id: "test",
        current_session: nil,
        request_id: 0,
        pending_requests: %{},
        stats: init_stats(),
        health_status: :healthy,
        started_at: System.monotonic_time(:millisecond)
      }

      {:ok, worker: worker_state}
    end

    @tag :unit
    test "binds worker to session on first checkout", %{worker: worker} do
      checkout_type = {:session, "user_123"}
      from = {self(), make_ref()}

      {:ok, _, updated_state, _} = PoolWorker.handle_checkout(checkout_type, from, worker, %{})

      assert updated_state.current_session == "user_123"
      assert updated_state.health_status == :healthy
      assert updated_state.stats.checkouts == 1
    end

    @tag :unit
    test "maintains session affinity for same session", %{worker: worker} do
      # First checkout
      checkout_type = {:session, "user_123"}
      from = {self(), make_ref()}
      {:ok, _, worker, _} = PoolWorker.handle_checkout(checkout_type, from, worker, %{})

      # Return to ready state
      {:ok, worker, _} = PoolWorker.handle_checkin(:ok, from, worker, %{})

      # Second checkout with same session
      {:ok, _, updated_state, _} = PoolWorker.handle_checkout(checkout_type, from, worker, %{})

      assert updated_state.current_session == "user_123"
      assert updated_state.stats.checkouts == 2
    end

    @tag :unit
    test "allows anonymous checkout", %{worker: worker} do
      checkout_type = :anonymous
      from = {self(), make_ref()}

      {:ok, _, updated_state, _} = PoolWorker.handle_checkout(checkout_type, from, worker, %{})

      assert updated_state.current_session == nil
      assert updated_state.health_status == :healthy
    end
  end

  describe "handle_checkin/4" do
    setup do
      # Create a complete worker state struct with proper stats
      worker_state = %DSPex.PythonBridge.PoolWorker{
        port: self(),
        python_path: "/usr/bin/python3",
        script_path: "test/script.py",
        worker_id: "test",
        current_session: "active_session",
        request_id: 0,
        pending_requests: %{},
        stats:
          Map.merge(init_stats(), %{
            requests_handled: 5,
            sessions_served: 1,
            checkouts: 1
          }),
        health_status: :healthy,
        started_at: System.monotonic_time(:millisecond)
      }

      {:ok, worker: worker_state}
    end

    @tag :unit
    test "returns worker to ready state", %{worker: worker} do
      from = {self(), make_ref()}

      {:ok, updated_state, _} = PoolWorker.handle_checkin(:ok, from, worker, %{})

      assert updated_state.health_status == :healthy
      # Session binding is maintained for affinity
      assert updated_state.current_session == "active_session"
    end

    @tag :unit
    test "handles checkin with errors", %{worker: worker} do
      from = {self(), make_ref()}
      checkin_type = {:error, :command_failed}

      {:ok, updated_state, _} = PoolWorker.handle_checkin(checkin_type, from, worker, %{})

      assert updated_state.health_status == :healthy
      assert updated_state.stats[:errors] == 1
    end
  end

  describe "terminate_worker/3" do
    @tag :unit
    test "cleans up worker resources" do
      worker_state = %DSPex.PythonBridge.PoolWorker{
        # Mock port as current process
        port: self(),
        python_path: "/usr/bin/python3",
        script_path: "test/script.py",
        worker_id: "test",
        current_session: nil,
        request_id: 0,
        pending_requests: %{},
        stats: init_stats(),
        health_status: :healthy,
        started_at: System.monotonic_time(:millisecond)
      }

      assert {:ok, _} = PoolWorker.terminate_worker(:shutdown, worker_state, %{})
    end
  end
end
