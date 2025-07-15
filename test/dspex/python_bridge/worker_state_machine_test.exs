defmodule DSPex.PythonBridge.WorkerStateMachineTest do
  use ExUnit.Case, async: true

  alias DSPex.PythonBridge.WorkerStateMachine

  describe "new/1" do
    test "creates a new state machine with initial state" do
      worker_id = "test_worker_123"
      sm = WorkerStateMachine.new(worker_id)

      assert sm.state == :initializing
      assert sm.health == :unknown
      assert sm.worker_id == worker_id
      assert sm.metadata == %{}
      assert sm.transition_history == []
      assert is_integer(sm.entered_state_at)
    end
  end

  describe "transition/4" do
    test "allows valid transitions" do
      sm = WorkerStateMachine.new("test_worker")

      # initializing -> ready
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete)
      assert sm.state == :ready
      assert length(sm.transition_history) == 1

      # ready -> busy
      {:ok, sm} = WorkerStateMachine.transition(sm, :busy, :checkout)
      assert sm.state == :busy
      assert length(sm.transition_history) == 2

      # busy -> ready
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :checkin_success)
      assert sm.state == :ready
      assert length(sm.transition_history) == 3
    end

    test "rejects invalid transitions" do
      sm = WorkerStateMachine.new("test_worker")

      # Cannot go directly from initializing to busy
      assert {:error, {:invalid_transition, :initializing, :busy}} =
               WorkerStateMachine.transition(sm, :busy, :checkout)

      # Cannot transition from terminated state
      {:ok, sm} = WorkerStateMachine.transition(sm, :terminated, :error)

      assert {:error, {:invalid_transition, :terminated, :ready}} =
               WorkerStateMachine.transition(sm, :ready, :init_complete)
    end

    test "records transition history with metadata" do
      sm = WorkerStateMachine.new("test_worker")
      metadata = %{session_id: "session_123", client_pid: self()}

      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete, metadata)

      [history_entry] = sm.transition_history
      assert history_entry.from == :initializing
      assert history_entry.to == :ready
      assert history_entry.reason == :init_complete
      assert history_entry.metadata == metadata
      assert is_integer(history_entry.duration_ms)
      assert is_integer(history_entry.timestamp)
    end

    test "merges metadata into worker metadata" do
      sm = WorkerStateMachine.new("test_worker")
      metadata = %{test_key: "test_value"}

      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete, metadata)

      assert sm.metadata == metadata
    end
  end

  describe "can_accept_work?/1" do
    test "returns true only for ready and healthy workers" do
      sm = WorkerStateMachine.new("test_worker")

      # Not ready yet
      refute WorkerStateMachine.can_accept_work?(sm)

      # Ready but unknown health
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete)
      refute WorkerStateMachine.can_accept_work?(sm)

      # Ready and healthy
      sm = WorkerStateMachine.update_health(sm, :healthy)
      assert WorkerStateMachine.can_accept_work?(sm)

      # Ready but unhealthy
      sm = WorkerStateMachine.update_health(sm, :unhealthy)
      refute WorkerStateMachine.can_accept_work?(sm)

      # Busy and healthy
      {:ok, sm} = WorkerStateMachine.transition(sm, :busy, :checkout)
      sm = WorkerStateMachine.update_health(sm, :healthy)
      refute WorkerStateMachine.can_accept_work?(sm)
    end
  end

  describe "should_remove?/1" do
    test "returns true for terminating and terminated states" do
      sm = WorkerStateMachine.new("test_worker")

      # Not removing in normal states
      refute WorkerStateMachine.should_remove?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete)
      refute WorkerStateMachine.should_remove?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :busy, :checkout)
      refute WorkerStateMachine.should_remove?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :degraded, :checkin_error)
      refute WorkerStateMachine.should_remove?(sm)

      # Should remove when terminating
      {:ok, sm} = WorkerStateMachine.transition(sm, :terminating, :shutdown)
      assert WorkerStateMachine.should_remove?(sm)

      # Should remove when terminated
      {:ok, sm} = WorkerStateMachine.transition(sm, :terminated, :terminate)
      assert WorkerStateMachine.should_remove?(sm)
    end
  end

  describe "update_health/2" do
    test "updates health status" do
      sm = WorkerStateMachine.new("test_worker")

      sm = WorkerStateMachine.update_health(sm, :healthy)
      assert sm.health == :healthy

      sm = WorkerStateMachine.update_health(sm, :unhealthy)
      assert sm.health == :unhealthy

      sm = WorkerStateMachine.update_health(sm, :unknown)
      assert sm.health == :unknown
    end
  end

  describe "degraded worker recovery" do
    test "degraded worker can recover to ready" do
      sm = WorkerStateMachine.new("test_worker")
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete)
      {:ok, sm} = WorkerStateMachine.transition(sm, :degraded, :health_check_failed)

      assert sm.state == :degraded
      refute WorkerStateMachine.can_accept_work?(sm)

      # Recovery path
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :health_restored)
      sm = WorkerStateMachine.update_health(sm, :healthy)

      assert sm.state == :ready
      assert WorkerStateMachine.can_accept_work?(sm)
    end
  end

  describe "complete worker lifecycle" do
    test "follows expected lifecycle path" do
      sm = WorkerStateMachine.new("test_worker")

      # Initialize
      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :init_complete)
      sm = WorkerStateMachine.update_health(sm, :healthy)
      assert WorkerStateMachine.can_accept_work?(sm)

      # Work cycle
      {:ok, sm} = WorkerStateMachine.transition(sm, :busy, :checkout)
      refute WorkerStateMachine.can_accept_work?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :checkin_success)
      assert WorkerStateMachine.can_accept_work?(sm)

      # Degradation and recovery
      {:ok, sm} = WorkerStateMachine.transition(sm, :degraded, :health_check_failed)
      sm = WorkerStateMachine.update_health(sm, :unhealthy)
      refute WorkerStateMachine.can_accept_work?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :ready, :health_restored)
      sm = WorkerStateMachine.update_health(sm, :healthy)
      assert WorkerStateMachine.can_accept_work?(sm)

      # Shutdown
      {:ok, sm} = WorkerStateMachine.transition(sm, :terminating, :shutdown)
      assert WorkerStateMachine.should_remove?(sm)

      {:ok, sm} = WorkerStateMachine.transition(sm, :terminated, :terminate)
      assert WorkerStateMachine.should_remove?(sm)

      # Verify history
      assert length(sm.transition_history) == 7
    end
  end
end
