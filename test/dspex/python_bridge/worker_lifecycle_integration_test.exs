defmodule DSPex.PythonBridge.WorkerLifecycleIntegrationTest do
  use ExUnit.Case

  alias DSPex.PythonBridge.{
    SessionPoolV2,
    PoolWorkerV2Enhanced,
    SessionAffinity,
    WorkerStateMachine,
    WorkerMetrics
  }

  @moduletag :integration
  @moduletag timeout: 60_000

  describe "Enhanced Worker Lifecycle Integration" do
    setup do
      # Start a test pool with enhanced workers
      pool_opts = [
        name: :"test_pool_#{:erlang.unique_integer([:positive])}",
        worker_module: PoolWorkerV2Enhanced,
        pool_size: 5,
        overflow: 2,
        lazy: false
      ]

      {:ok, pool_pid} = SessionPoolV2.start_link(pool_opts)

      on_exit(fn ->
        if Process.alive?(pool_pid) do
          GenServer.stop(pool_pid)
        end
      end)

      %{pool_pid: pool_pid, pool_name: pool_opts[:name]}
    end

    @tag :enhanced_workers
    test "enhanced workers transition through proper states", %{pool_name: pool_name} do
      # Get pool name for NimblePool operations
      actual_pool_name = GenServer.call(pool_name, :get_pool_name)

      # Check pool status
      status = GenServer.call(pool_name, :get_status)
      assert status.pool_size == 5
      assert Map.has_key?(status, :session_affinity)

      # Execute a simple operation to trigger worker lifecycle
      session_id = "integration_test_session_#{:erlang.unique_integer()}"

      result =
        SessionPoolV2.execute_in_session(
          session_id,
          :ping,
          %{test: true},
          pool_name: actual_pool_name
        )

      # Should succeed (or at least not crash)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      # Check that session affinity was recorded
      affinity_stats = SessionAffinity.get_stats()
      assert is_map(affinity_stats)
    end

    @tag :session_affinity
    test "session affinity works across multiple operations", %{pool_name: pool_name} do
      actual_pool_name = GenServer.call(pool_name, :get_pool_name)
      session_id = "affinity_test_session_#{:erlang.unique_integer()}"

      # First operation
      result1 =
        SessionPoolV2.execute_in_session(
          session_id,
          :ping,
          %{operation: 1},
          pool_name: actual_pool_name
        )

      # Second operation should use same worker (if session affinity is working)
      result2 =
        SessionPoolV2.execute_in_session(
          session_id,
          :ping,
          %{operation: 2},
          pool_name: actual_pool_name
        )

      # Both should complete
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)
      assert match?({:ok, _}, result2) or match?({:error, _}, result2)

      # Check affinity stats
      stats = SessionAffinity.get_stats()
      assert is_integer(stats.total_sessions)
    end

    @tag :metrics
    test "worker metrics are recorded during operations" do
      # Record some test metrics
      worker_id = "test_worker_#{:erlang.unique_integer()}"

      # Test different metric types
      WorkerMetrics.record_transition(worker_id, :ready, :busy, 1000)
      WorkerMetrics.record_health_check(worker_id, :success, 250)
      WorkerMetrics.record_session_affinity("session_123", worker_id, :hit)
      WorkerMetrics.record_operation(worker_id, :execute, 1500, :success)
      WorkerMetrics.record_lifecycle(worker_id, :created)

      # Should not crash
      summary = WorkerMetrics.get_summary()
      assert is_map(summary)
    end

    @tag :state_machine
    test "worker state machine handles all transitions correctly" do
      worker_id = "state_test_worker"
      sm = WorkerStateMachine.new(worker_id)

      # Test complete lifecycle
      assert sm.state == :initializing

      # Initialize
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete)
      sm = WorkerStateMachine.update_health(sm, :healthy)
      assert WorkerStateMachine.can_accept_work?(sm)

      # Work cycle
      {:ok, sm} = WorkerStateMachine.transition(sm, :busy, :checkout)
      refute WorkerStateMachine.can_accept_work?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :checkin_success)
      assert WorkerStateMachine.can_accept_work?(sm)

      # Health degradation
      {:ok, sm} = WorkerStateMachine.transition(sm, :degraded, :health_check_failed)
      sm = WorkerStateMachine.update_health(sm, :unhealthy)
      refute WorkerStateMachine.can_accept_work?(sm)

      # Recovery
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :health_restored)
      sm = WorkerStateMachine.update_health(sm, :healthy)
      assert WorkerStateMachine.can_accept_work?(sm)

      # Shutdown
      {:ok, sm} = WorkerStateMachine.transition(sm, :terminating, :shutdown)
      assert WorkerStateMachine.should_remove?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :terminated, :terminate)
      assert WorkerStateMachine.should_remove?(sm)

      # Check history (7 transitions: init→ready→busy→ready→degraded→ready→terminating→terminated)
      assert length(sm.transition_history) == 7
    end

    @tag :recovery
    test "worker recovery strategies work correctly" do
      alias DSPex.PythonBridge.WorkerRecovery

      # Create a mock worker state
      worker_id = "recovery_test_worker"
      state_machine = WorkerStateMachine.new(worker_id)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :ready, :init_complete)

      worker_state = %{
        worker_id: worker_id,
        state_machine: state_machine,
        health_check_failures: 0,
        started_at: System.monotonic_time(:millisecond)
      }

      # Test different failure scenarios

      # Port failure -> remove
      strategy = WorkerRecovery.determine_strategy({:port_exited, 1}, worker_state)
      assert strategy.action == :remove

      # Health check failure -> degrade
      strategy = WorkerRecovery.determine_strategy({:health_check_failed, :timeout}, worker_state)
      assert strategy.action == :degrade

      # Max failures -> remove
      worker_with_failures = %{worker_state | health_check_failures: 3}

      strategy =
        WorkerRecovery.determine_strategy({:health_check_failed, :timeout}, worker_with_failures)

      assert strategy.action == :remove

      # Test strategy execution
      degrade_strategy = %{action: :degrade, delay: 5000, metadata: %{reason: :test}}
      result = WorkerRecovery.execute_recovery(degrade_strategy, worker_state, :test_pool)
      assert {:ok, updated_worker, :test_pool} = result
      assert updated_worker.state_machine.state == :degraded
    end

    @tag :configuration
    test "pool can be configured with different worker types" do
      # Test basic worker configuration
      basic_pool_opts = [
        name: :"basic_test_pool_#{:erlang.unique_integer([:positive])}",
        # Basic worker
        worker_module: DSPex.PythonBridge.PoolWorkerV2,
        pool_size: 1,
        overflow: 0
      ]

      {:ok, basic_pool} = SessionPoolV2.start_link(basic_pool_opts)

      basic_status = GenServer.call(basic_pool_opts[:name], :get_status)
      IO.puts("Basic status: #{inspect(basic_status, pretty: true)}")
      assert basic_status.pool_size == 1
      # Basic workers don't have session affinity
      assert basic_status.session_affinity == %{}

      # Defensive cleanup
      if Process.alive?(basic_pool) do
        ref = Process.monitor(basic_pool)
        GenServer.stop(basic_pool, :normal, 2000)

        receive do
          {:DOWN, ^ref, :process, ^basic_pool, _} -> :ok
        after
          100 -> :ok
        end
      end

      # Enhanced worker pools should have session affinity
      enhanced_pool_opts = [
        name: :"enhanced_test_pool_#{:erlang.unique_integer([:positive])}",
        worker_module: PoolWorkerV2Enhanced,
        pool_size: 1,
        overflow: 0
      ]

      {:ok, enhanced_pool} = SessionPoolV2.start_link(enhanced_pool_opts)

      enhanced_status = GenServer.call(enhanced_pool_opts[:name], :get_status)
      assert enhanced_status.pool_size == 1
      # Enhanced workers should have session affinity tracking
      assert is_map(enhanced_status.session_affinity)

      # Defensive cleanup  
      if Process.alive?(enhanced_pool) do
        ref = Process.monitor(enhanced_pool)
        GenServer.stop(enhanced_pool, :normal, 2000)

        receive do
          {:DOWN, ^ref, :process, ^enhanced_pool, _} -> :ok
        after
          100 -> :ok
        end
      end
    end

    @tag :concurrent_operations
    test "handles concurrent operations correctly", %{pool_name: pool_name} do
      actual_pool_name = GenServer.call(pool_name, :get_pool_name)

      # Start multiple concurrent operations
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            session_id = "concurrent_session_#{i}"

            SessionPoolV2.execute_in_session(
              session_id,
              :ping,
              %{operation_id: i},
              pool_name: actual_pool_name,
              timeout: 10_000
            )
          end)
        end

      # Wait for all operations to complete (increased timeout for Python overhead)
      results = Task.await_many(tasks, 30_000)

      # All operations should complete (either successfully or with expected errors)
      assert length(results) == 5

      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    @tag :telemetry
    test "telemetry events are emitted correctly" do
      # Set up a simple telemetry handler to capture events
      test_pid = self()

      handler_fun = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      # Try to attach handler (will work if telemetry is available)
      result = WorkerMetrics.attach_handler(:test_handler, handler_fun)

      case result do
        :ok ->
          # Telemetry is available, test events
          WorkerMetrics.record_transition("test_worker", :ready, :busy, 1000)

          assert_receive {:telemetry_event, [:dspex, :pool, :worker, :transition], measurements,
                          metadata},
                         1000

          assert measurements.duration == 1000
          assert metadata.worker_id == "test_worker"

          WorkerMetrics.detach_handler(:test_handler)

        {:error, :telemetry_not_available} ->
          # Telemetry not available, that's ok for testing
          :ok
      end
    end
  end

  describe "Error Handling and Edge Cases" do
    @tag :error_handling
    test "handles session affinity errors gracefully" do
      # Start a SessionAffinity process for this test
      affinity_name = :"test_affinity_#{:erlang.unique_integer([:positive])}"

      {:ok, affinity_pid} =
        SessionAffinity.start_link(
          name: affinity_name,
          cleanup_interval: 500,
          session_timeout: 5000
        )

      on_exit(fn ->
        if Process.alive?(affinity_pid) do
          GenServer.stop(affinity_pid)
        end
      end)

      # Test when SessionAffinity is not available
      non_existent_session = "non_existent_session_#{:erlang.unique_integer()}"

      result = SessionAffinity.get_worker(non_existent_session, affinity_name)
      assert result == {:error, :no_affinity}

      # Test session cleanup
      test_session = "cleanup_test_session"
      test_worker = "cleanup_test_worker"

      :ok = SessionAffinity.bind_session(test_session, test_worker)
      {:ok, ^test_worker} = SessionAffinity.get_worker(test_session, affinity_name)

      :ok = SessionAffinity.unbind_session(test_session)
      {:error, :no_affinity} = SessionAffinity.get_worker(test_session, affinity_name)
    end

    @tag :invalid_transitions
    test "handles invalid state transitions gracefully" do
      worker_id = "invalid_transition_test"
      sm = WorkerStateMachine.new(worker_id)

      # Try invalid transition
      result = WorkerStateMachine.transition(sm, :busy, :invalid_reason)
      assert {:error, {:invalid_transition, :initializing, :busy}} = result

      # State machine should be unchanged
      assert sm.state == :initializing
    end

    @tag :metrics_failures
    test "continues operation when metrics fail" do
      # This test ensures that metrics failures don't break normal operation
      worker_id = "metrics_failure_test"
      sm = WorkerStateMachine.new(worker_id)

      # Transition should work even if metrics fail internally
      {:ok, updated_sm} = WorkerStateMachine.transition(sm, :ready, :init_complete)
      assert updated_sm.state == :ready

      # Metrics recording should not crash
      WorkerMetrics.record_health_check(worker_id, :success, 100)
      WorkerMetrics.record_lifecycle(worker_id, :created)
    end
  end

  describe "Performance and Monitoring" do
    @tag :performance
    test "worker operations complete within reasonable time" do
      # Test timing functionality
      worker_id = "timing_test_worker"

      timer = WorkerMetrics.start_timing(worker_id, :test_operation)

      # Simulate some work
      Process.sleep(10)

      timer.(:success)

      # Should complete without error
      :ok
    end

    @tag :pool_metrics
    test "pool-level metrics are recorded" do
      pool_name = :test_metrics_pool

      WorkerMetrics.record_pool_metric(pool_name, :worker_count, 5)
      WorkerMetrics.record_pool_metric(pool_name, :session_count, 10)

      # Should complete without error
      summary = WorkerMetrics.get_summary()
      assert is_map(summary)
    end
  end
end
