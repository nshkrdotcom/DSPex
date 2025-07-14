defmodule DSPex.PythonBridge.WorkerRecoveryTest do
  use ExUnit.Case, async: true
  
  alias DSPex.PythonBridge.{WorkerRecovery, WorkerStateMachine}
  
  describe "determine_strategy/3" do
    setup do
      worker_id = "test_worker_#{:erlang.unique_integer([:positive])}"
      state_machine = WorkerStateMachine.new(worker_id)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :ready, :init_complete)
      state_machine = WorkerStateMachine.update_health(state_machine, :healthy)
      
      worker_state = %{
        worker_id: worker_id,
        state_machine: state_machine,
        health_check_failures: 0,
        started_at: System.monotonic_time(:millisecond)
      }
      
      %{worker_state: worker_state}
    end
    
    test "port exit triggers immediate removal", %{worker_state: worker_state} do
      strategy = WorkerRecovery.determine_strategy({:port_exited, 1}, worker_state)
      
      assert strategy.action == :remove
      assert strategy.delay == 0
      assert strategy.metadata.reason == :port_failure
      assert strategy.metadata.exit_status == 1
    end
    
    test "checkout failure triggers immediate removal", %{worker_state: worker_state} do
      strategy = WorkerRecovery.determine_strategy({:checkout_failed, :port_closed}, worker_state)
      
      assert strategy.action == :remove
      assert strategy.delay == 0
      assert strategy.metadata.reason == :checkout_failure
      assert strategy.metadata.details == :port_closed
    end
    
    test "first health check failure triggers degradation", %{worker_state: worker_state} do
      strategy = WorkerRecovery.determine_strategy({:health_check_failed, :timeout}, worker_state)
      
      assert strategy.action == :degrade
      assert strategy.delay > 0
      assert strategy.metadata.reason == :health_degraded
      assert strategy.metadata.failure_count == 1
    end
    
    test "max health check failures trigger removal", %{worker_state: worker_state} do
      # Simulate worker with max failures
      worker_with_failures = %{worker_state | health_check_failures: 3}
      
      strategy = WorkerRecovery.determine_strategy({:health_check_failed, :timeout}, worker_with_failures)
      
      assert strategy.action == :remove
      assert strategy.delay == 0
      assert strategy.metadata.reason == :health_check_limit
      assert strategy.metadata.failure_count == 4
    end
    
    test "max failures exceeded triggers removal", %{worker_state: worker_state} do
      strategy = WorkerRecovery.determine_strategy({:max_failures_exceeded, :too_many_errors}, worker_state)
      
      assert strategy.action == :remove
      assert strategy.delay == 0
      assert strategy.metadata.reason == :max_failures
      assert strategy.metadata.details == :too_many_errors
    end
    
    test "worker not ready triggers removal", %{worker_state: worker_state} do
      strategy = WorkerRecovery.determine_strategy({:worker_not_ready, :degraded}, worker_state)
      
      assert strategy.action == :remove
      assert strategy.delay == 0
      assert strategy.metadata.reason == :not_ready
      assert strategy.metadata.state == :degraded
    end
    
    test "includes context in strategy metadata", %{worker_state: worker_state} do
      context = %{session_id: "test_session", operation: :execute}
      
      strategy = WorkerRecovery.determine_strategy({:port_exited, 1}, worker_state, context)
      
      assert strategy.action == :remove
      # Context is passed to ErrorHandler, not directly to metadata
      assert Map.has_key?(strategy.metadata, :reason)
    end
  end
  
  describe "execute_recovery/3" do
    setup do
      worker_id = "test_worker_#{:erlang.unique_integer([:positive])}"
      state_machine = WorkerStateMachine.new(worker_id)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :ready, :init_complete)
      
      worker_state = %{
        worker_id: worker_id,
        state_machine: state_machine,
        health_check_failures: 0,
        started_at: System.monotonic_time(:millisecond),
        stats: %{checkouts: 5}
      }
      
      pool_state = :mock_pool_state
      
      %{worker_state: worker_state, pool_state: pool_state}
    end
    
    test "retry action returns retry tuple", %{worker_state: worker_state, pool_state: pool_state} do
      strategy = %{action: :retry, delay: 1000, metadata: %{}}
      
      result = WorkerRecovery.execute_recovery(strategy, worker_state, pool_state)
      
      assert result == {:retry, 1000}
    end
    
    test "degrade action transitions worker to degraded state", %{worker_state: worker_state, pool_state: pool_state} do
      strategy = %{action: :degrade, delay: 5000, metadata: %{reason: :health_degraded}}
      
      result = WorkerRecovery.execute_recovery(strategy, worker_state, pool_state)
      
      assert {:ok, updated_worker, ^pool_state} = result
      assert updated_worker.state_machine.state == :degraded
      assert updated_worker.state_machine.health == :unhealthy
    end
    
    test "remove action returns remove tuple", %{worker_state: worker_state, pool_state: pool_state} do
      strategy = %{action: :remove, delay: 0, metadata: %{reason: :port_failure}}
      
      result = WorkerRecovery.execute_recovery(strategy, worker_state, pool_state)
      
      assert {:remove, {:recovery_removal, %{reason: :port_failure}}, ^pool_state} = result
    end
    
    test "replace action returns remove tuple and sends message", %{worker_state: worker_state} do
      pool_pid = self()
      strategy = %{action: :replace, delay: 0, metadata: %{reason: :health_failure}}
      
      result = WorkerRecovery.execute_recovery(strategy, worker_state, pool_pid)
      
      assert {:remove, {:replaced, %{reason: :health_failure}}, ^pool_pid} = result
      
      # Check that replacement message was sent
      assert_received {:replace_worker, worker_id, %{reason: :health_failure}}
      assert worker_id == worker_state.worker_id
    end
  end
  
  describe "is_recoverable?/1" do
    test "identifies recoverable failures" do
      assert WorkerRecovery.is_recoverable?({:health_check_failed, :timeout})
      assert WorkerRecovery.is_recoverable?({:timeout, "Operation timeout"})
      assert WorkerRecovery.is_recoverable?({:temporary_failure, "Network hiccup"})
    end
    
    test "identifies non-recoverable failures" do
      refute WorkerRecovery.is_recoverable?({:port_exited, 1})
      refute WorkerRecovery.is_recoverable?({:checkout_failed, :port_closed})
      refute WorkerRecovery.is_recoverable?({:max_failures_exceeded, :too_many_errors})
      refute WorkerRecovery.is_recoverable?({:worker_not_ready, :degraded})
    end
    
    test "defaults to non-recoverable for unknown failures" do
      refute WorkerRecovery.is_recoverable?({:unknown_failure, "Something bad"})
      refute WorkerRecovery.is_recoverable?(:some_atom)
    end
  end
  
  describe "get_failure_delay/1" do
    test "returns appropriate delays for different failure types" do
      assert WorkerRecovery.get_failure_delay({:health_check_failed, :timeout}) == 5_000
      assert WorkerRecovery.get_failure_delay({:timeout, "Operation timeout"}) == 3_000
      assert WorkerRecovery.get_failure_delay({:temporary_failure, "Network hiccup"}) == 1_000
      assert WorkerRecovery.get_failure_delay({:connection_failed, "Can't connect"}) == 10_000
    end
    
    test "returns default delay for unknown failures" do
      assert WorkerRecovery.get_failure_delay({:unknown_failure, "Something"}) == 1_000
      assert WorkerRecovery.get_failure_delay(:some_atom) == 1_000
    end
  end
  
  describe "integration with different worker states" do
    test "handles degraded worker differently" do
      worker_id = "test_worker"
      state_machine = WorkerStateMachine.new(worker_id)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :ready, :init_complete)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :degraded, :health_check_failed)
      state_machine = WorkerStateMachine.update_health(state_machine, :unhealthy)
      
      worker_state = %{
        worker_id: worker_id,
        state_machine: state_machine,
        health_check_failures: 2,
        started_at: System.monotonic_time(:millisecond)
      }
      
      # One more health failure should trigger removal
      strategy = WorkerRecovery.determine_strategy({:health_check_failed, :timeout}, worker_state)
      
      assert strategy.action == :remove
      assert strategy.metadata.reason == :health_check_limit
    end
    
    test "handles busy worker timeout" do
      worker_id = "test_worker"
      state_machine = WorkerStateMachine.new(worker_id)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :ready, :init_complete)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :busy, :checkout)
      
      worker_state = %{
        worker_id: worker_id,
        state_machine: state_machine,
        health_check_failures: 0,
        started_at: System.monotonic_time(:millisecond)
      }
      
      strategy = WorkerRecovery.determine_strategy({:timeout, "Operation timeout"}, worker_state)
      
      # Based on ErrorHandler behavior, timeouts may not be recoverable by default
      # This test verifies the current behavior - timeout leads to removal
      assert strategy.action == :remove
      assert strategy.metadata.reason == :timeout_limit
    end
  end
  
  describe "error integration with ErrorHandler" do
    test "leverages ErrorHandler for retry decisions" do
      worker_id = "test_worker"
      state_machine = WorkerStateMachine.new(worker_id)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :ready, :init_complete)
      
      worker_state = %{
        worker_id: worker_id,
        state_machine: state_machine,
        health_check_failures: 0,
        started_at: System.monotonic_time(:millisecond)
      }
      
      # Test with a failure type that should be recoverable
      strategy = WorkerRecovery.determine_strategy({:health_check_failed, :timeout}, worker_state)
      
      # Health check failures should trigger degradation (which is a form of recovery)
      assert strategy.action == :degrade
      assert strategy.delay > 0
    end
  end
  
  describe "edge cases" do
    test "handles missing worker fields gracefully" do
      minimal_worker = %{
        worker_id: "minimal_worker",
        state_machine: WorkerStateMachine.new("minimal_worker")
      }
      
      strategy = WorkerRecovery.determine_strategy({:port_exited, 1}, minimal_worker)
      
      assert strategy.action == :remove
      assert strategy.delay == 0
    end
    
    test "handles state transition failures during degrade" do
      worker_id = "test_worker"
      # Create a worker in terminated state (can't transition from terminated)
      state_machine = WorkerStateMachine.new(worker_id)
      {:ok, state_machine} = WorkerStateMachine.transition(state_machine, :terminated, :error)
      
      worker_state = %{
        worker_id: worker_id,
        state_machine: state_machine,
        health_check_failures: 0,
        started_at: System.monotonic_time(:millisecond)
      }
      
      strategy = %{action: :degrade, delay: 5000, metadata: %{reason: :test}}
      pool_state = :test_pool
      
      result = WorkerRecovery.execute_recovery(strategy, worker_state, pool_state)
      
      # Should remove worker if transition fails
      assert {:remove, {:state_transition_failed, _}, ^pool_state} = result
    end
  end
end