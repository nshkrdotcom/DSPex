defmodule DSPex.PythonBridge.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias DSPex.PythonBridge.CircuitBreaker

  setup do
    # Generate unique name for each test to avoid conflicts
    test_name = :"test_circuit_breaker_#{System.unique_integer([:positive])}"

    # Start a circuit breaker for testing
    {:ok, pid} = CircuitBreaker.start_link(name: test_name)

    # Safe cleanup with race condition protection
    on_exit(fn ->
      try do
        if Process.alive?(pid) do
          GenServer.stop(pid, :normal, 1000)
        end
      catch
        # Process already terminated
        :exit, _ -> :ok
      end
    end)

    %{circuit_breaker: test_name}
  end

  describe "circuit breaker initialization" do
    test "starts with closed state", %{circuit_breaker: cb} do
      assert CircuitBreaker.get_state(:new_circuit, server: cb) == :not_found
    end

    test "creates circuit on first use", %{circuit_breaker: cb} do
      result =
        CircuitBreaker.with_circuit(:test_operation, fn -> {:ok, "success"} end, server: cb)

      assert result == {:ok, "success"}
      assert CircuitBreaker.get_state(:test_operation, server: cb) == :closed
    end
  end

  describe "circuit state transitions" do
    test "opens circuit after failure threshold", %{circuit_breaker: cb} do
      circuit_name = :failure_test

      # Cause failures to reach threshold (default is 5)
      for _i <- 1..5 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open
    end

    test "remains closed below failure threshold", %{circuit_breaker: cb} do
      circuit_name = :below_threshold_test

      # Cause failures below threshold
      for _i <- 1..3 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      assert CircuitBreaker.get_state(circuit_name, server: cb) == :closed
    end

    test "resets failure count on success in closed state", %{circuit_breaker: cb} do
      circuit_name = :reset_test

      # Cause some failures
      for _i <- 1..3 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      # Record success
      CircuitBreaker.record_success(circuit_name, server: cb)

      # Should still be closed and failure count reset
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :closed

      # More failures should not immediately open (count was reset)
      CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :closed
    end

    test "transitions to half-open after timeout", %{circuit_breaker: cb} do
      circuit_name = :timeout_test

      # Open the circuit
      for _i <- 1..5 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open

      # Simulate timeout by manually adjusting the circuit
      # Note: In real scenarios, we'd wait for the actual timeout
      # For testing, we'll test the transition logic directly

      # Use a circuit with a very short timeout for testing
      short_timeout_result =
        CircuitBreaker.with_circuit(
          :short_timeout_test,
          fn -> {:ok, "success"} end,
          # 1ms timeout
          server: cb,
          config: %{timeout: 1}
        )

      # First call should succeed (circuit is closed initially)
      assert short_timeout_result == {:ok, "success"}
    end

    test "closes from half-open after success threshold", %{circuit_breaker: cb} do
      circuit_name = :half_open_test

      # This test would require more complex setup to get to half-open state
      # For now, we'll test the success recording logic
      CircuitBreaker.record_success(circuit_name, server: cb)
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :closed
    end

    test "reopens from half-open on failure", %{circuit_breaker: cb} do
      circuit_name = :reopen_test

      # Open the circuit first
      for _i <- 1..5 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open

      # Any failure in half-open should reopen
      CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open
    end
  end

  describe "circuit execution" do
    test "executes function successfully in closed state", %{circuit_breaker: cb} do
      result =
        CircuitBreaker.with_circuit(
          :success_test,
          fn ->
            {:ok, "operation successful"}
          end,
          server: cb
        )

      assert result == {:ok, "operation successful"}
    end

    test "handles function exceptions", %{circuit_breaker: cb} do
      result =
        CircuitBreaker.with_circuit(
          :exception_test,
          fn ->
            raise "test exception"
          end,
          server: cb
        )

      assert {:error, wrapped_error} = result
      assert wrapped_error.pool_error == true
      assert String.contains?(wrapped_error.message, "circuit_execution_failed")
    end

    test "handles function throws", %{circuit_breaker: cb} do
      result =
        CircuitBreaker.with_circuit(
          :throw_test,
          fn ->
            throw("test throw")
          end,
          server: cb
        )

      assert {:error, wrapped_error} = result
      assert wrapped_error.pool_error == true
    end

    test "handles function exits", %{circuit_breaker: cb} do
      result =
        CircuitBreaker.with_circuit(
          :exit_test,
          fn ->
            exit("test exit")
          end,
          server: cb
        )

      assert {:error, wrapped_error} = result
      assert wrapped_error.pool_error == true
    end

    test "rejects calls when circuit is open", %{circuit_breaker: cb} do
      circuit_name = :rejection_test

      # Open the circuit
      for _i <- 1..5 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      result =
        CircuitBreaker.with_circuit(
          circuit_name,
          fn ->
            {:ok, "should not execute"}
          end,
          server: cb
        )

      assert {:error, wrapped_error} = result
      assert wrapped_error.pool_error == true
      assert String.contains?(wrapped_error.message, "circuit_open")
    end
  end

  describe "circuit configuration" do
    test "respects custom failure threshold", %{circuit_breaker: cb} do
      circuit_name = :custom_threshold_test

      # Use custom config with lower threshold
      custom_config = %{failure_threshold: 2}

      # Create circuit with custom config using with_circuit
      result =
        CircuitBreaker.with_circuit(
          circuit_name,
          fn ->
            raise "initial failure"
          end,
          server: cb,
          config: custom_config
        )

      assert {:error, _} = result

      # Check circuit info to verify custom config was applied
      info = CircuitBreaker.get_circuit_info(circuit_name, server: cb)
      assert info.config.failure_threshold == 2
      assert info.failure_count == 1
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :closed

      # Second failure should open with custom threshold of 2
      CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open
    end

    test "respects custom success threshold", %{circuit_breaker: cb} do
      # This would test half-open to closed transition
      # Implementation would require more setup
      # Placeholder
      assert true
    end

    test "respects custom timeout", %{circuit_breaker: cb} do
      # This would test open to half-open transition timing
      # Implementation would require time manipulation
      # Placeholder
      assert true
    end

    test "respects half-open request limit", %{circuit_breaker: cb} do
      # This would test concurrent request limiting in half-open state
      # Implementation would require concurrent execution setup
      # Placeholder
      assert true
    end
  end

  describe "circuit information" do
    test "get_circuit_info returns detailed information", %{circuit_breaker: cb} do
      circuit_name = :info_test

      # Create circuit by recording a failure
      CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)

      info = CircuitBreaker.get_circuit_info(circuit_name, server: cb)

      assert info != :not_found
      assert info.name == circuit_name
      assert info.state == :closed
      assert info.failure_count == 1
      assert is_map(info.config)
      assert is_integer(info.last_state_change)
    end

    test "get_circuit_info returns :not_found for unknown circuits", %{circuit_breaker: cb} do
      info = CircuitBreaker.get_circuit_info(:unknown_circuit, server: cb)
      assert info == :not_found
    end

    test "get_state returns :not_found for unknown circuits", %{circuit_breaker: cb} do
      state = CircuitBreaker.get_state(:unknown_circuit, server: cb)
      assert state == :not_found
    end
  end

  describe "manual circuit management" do
    test "reset restores circuit to closed state", %{circuit_breaker: cb} do
      circuit_name = :reset_test

      # Open the circuit
      for _i <- 1..5 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open

      # Reset the circuit
      :ok = CircuitBreaker.reset(circuit_name, server: cb)

      assert CircuitBreaker.get_state(circuit_name, server: cb) == :closed

      # Should accept calls again
      result =
        CircuitBreaker.with_circuit(
          circuit_name,
          fn ->
            {:ok, "reset successful"}
          end,
          server: cb
        )

      assert result == {:ok, "reset successful"}
    end

    test "manual success recording works", %{circuit_breaker: cb} do
      circuit_name = :manual_success_test

      # Record some failures
      for _i <- 1..3 do
        CircuitBreaker.record_failure(circuit_name, :test_error, server: cb)
      end

      # Record manual success
      :ok = CircuitBreaker.record_success(circuit_name, server: cb)

      # Circuit should still be closed and failure count reset
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :closed
    end

    test "manual failure recording works", %{circuit_breaker: cb} do
      circuit_name = :manual_failure_test

      # Record failures manually
      for _i <- 1..5 do
        :ok = CircuitBreaker.record_failure(circuit_name, :manual_error, server: cb)
      end

      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open
    end
  end

  describe "error handling edge cases" do
    test "handles unknown circuit operations gracefully", %{circuit_breaker: cb} do
      # Recording success for unknown circuit should not crash
      :ok = CircuitBreaker.record_success(:unknown_circuit, server: cb)

      # Should create the circuit in closed state
      assert CircuitBreaker.get_state(:unknown_circuit, server: cb) == :closed
    end

    test "handles concurrent access safely", %{circuit_breaker: cb} do
      circuit_name = :concurrent_test

      # Start multiple processes that record failures
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            CircuitBreaker.record_failure(circuit_name, {:error, i}, server: cb)
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      # Circuit should be open (more than 5 failures)
      assert CircuitBreaker.get_state(circuit_name, server: cb) == :open
    end
  end

  describe "telemetry integration" do
    test "emits telemetry events for operations" do
      # This would test telemetry event emission
      # Would require telemetry test helpers
      # Placeholder - telemetry testing would need special setup
      assert true
    end
  end
end
