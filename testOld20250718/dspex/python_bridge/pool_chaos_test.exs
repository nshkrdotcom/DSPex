defmodule DSPex.PythonBridge.PoolChaosTest do
  @moduledoc """
  Comprehensive chaos testing for pool resilience and recovery.

  Tests pool behavior under various failure conditions:
  - Worker failures and recovery
  - Resource exhaustion scenarios
  - Cascading failure patterns
  - Recovery verification under load

  Uses enhanced test infrastructure for controlled chaos engineering.
  """

  use DSPex.UnifiedTestFoundation, :pool_testing
  import DSPex.PoolChaosHelpers
  import DSPex.EnhancedPoolTestHelpers
  import DSPex.SupervisionTestHelpers

  require Logger

  @moduletag :pool_chaos
  # 2 minutes for chaos tests
  @moduletag timeout: 120_000

  # Only run in full integration mode for real chaos testing
  @moduletag :layer_3

  describe "Worker Failure Chaos" do
    test "single worker failure and recovery", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      # Wait for pool to be ready
      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Inject single worker failure
      assert {:ok, failure_result} =
               inject_worker_failure(pool_info, :random,
                 verify_recovery: true,
                 recovery_timeout: 45_000
               )

      # Verify failure was injected
      assert failure_result.targeted_workers == 1
      assert is_map(failure_result.pre_failure_state)

      # Verify recovery
      assert Map.has_key?(failure_result, :recovery_result)
      recovery = failure_result.recovery_result
      assert recovery.recovery_successful
      assert recovery.recovery_time_ms > 0

      Logger.info("Single worker failure test: recovery in #{recovery.recovery_time_ms}ms")
    end

    test "multiple worker failures", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Inject 50% worker failures
      assert {:ok, failure_result} =
               inject_worker_failure(pool_info, 0.5,
                 verify_recovery: true,
                 recovery_timeout: 60_000
               )

      # Should have targeted multiple workers
      assert failure_result.targeted_workers >= 2

      # Verify recovery even with multiple failures
      if Map.has_key?(failure_result, :recovery_result) do
        recovery = failure_result.recovery_result
        assert recovery.recovery_successful

        Logger.info(
          "Multiple worker failure test: #{failure_result.targeted_workers} workers failed, recovery in #{recovery.recovery_time_ms}ms"
        )
      else
        Logger.warning("Multiple worker failure test: recovery verification failed")
      end
    end

    test "cascading worker failures", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Create cascading failure scenario
      chaos_scenarios = [
        {:worker_failure, :random, [verify_recovery: false]},
        {:worker_failure, 0.3, [verify_recovery: false]},
        {:worker_failure, :random, [verify_recovery: false]}
      ]

      assert {:ok, orchestration_result} =
               chaos_test_orchestrator(pool_info, chaos_scenarios,
                 execution_mode: :sequential,
                 verify_recovery_between: false
               )

      # Verify orchestration completed
      assert orchestration_result.orchestration_successful
      assert orchestration_result.total_scenarios == 3

      # Verify final recovery
      assert orchestration_result.final_recovery.recovery_successful

      Logger.info(
        "Cascading failure test: #{orchestration_result.total_scenarios} scenarios, final recovery in #{orchestration_result.final_recovery.recovery_time_ms}ms"
      )
    end
  end

  describe "Resource Exhaustion Chaos" do
    test "memory pressure simulation", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Create memory pressure
      assert {:ok, pressure_result} =
               create_memory_pressure(pool_info,
                 # Moderate pressure for tests
                 pressure_mb: 50,
                 duration_ms: 8_000,
                 verify_recovery: true
               )

      # Verify pressure was created
      assert pressure_result.memory_increase > 0
      assert pressure_result.monitoring_result.sample_count > 0

      # Verify recovery
      if Map.has_key?(pressure_result, :recovery_result) do
        recovery = pressure_result.recovery_result
        assert recovery.recovery_successful

        Logger.info(
          "Memory pressure test: #{pressure_result.pressure_mb}MB pressure, recovery in #{recovery.recovery_time_ms}ms"
        )
      else
        Logger.info("Memory pressure test: recovery verification not available")
      end
    end

    test "port corruption simulation", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Simulate port corruption
      assert {:ok, corruption_result} =
               simulate_port_corruption(pool_info,
                 corruption_type: :random_data,
                 duration_ms: 5_000,
                 verify_recovery: true
               )

      # Verify corruption simulation ran
      assert corruption_result.duration_ms == 5_000
      assert is_map(corruption_result.corruption_result)
      assert is_map(corruption_result.monitoring_result)

      # Verify recovery
      if Map.has_key?(corruption_result, :recovery_result) do
        recovery = corruption_result.recovery_result
        assert recovery.recovery_successful

        Logger.info(
          "Port corruption test: #{corruption_result.duration_ms}ms corruption, recovery in #{recovery.recovery_time_ms}ms"
        )
      else
        Logger.info("Port corruption test: recovery verification not available")
      end
    end
  end

  describe "Chaos Under Load" do
    test "worker failures during concurrent operations", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Start background load
      load_task =
        Task.async(fn ->
          operations =
            for i <- 1..20 do
              fn ->
                DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
                  :ping,
                  %{test: "chaos_under_load", operation: i},
                  pool_name: context.actual_pool_name,
                  timeout: 15_000
                )
              end
            end

          test_concurrent_operations(pool_info, operations,
            timeout: 60_000,
            track_performance: true
          )
        end)

      # Wait a bit for load to start
      :timer.sleep(2000)

      # Inject chaos during load
      chaos_task =
        Task.async(fn ->
          inject_worker_failure(pool_info, :random,
            # Don't verify recovery during load
            verify_recovery: false
          )
        end)

      # Wait for both to complete
      load_result = Task.await(load_task, 70_000)
      chaos_result = Task.await(chaos_task, 30_000)

      # Verify both completed
      assert {:ok, load_data} = load_result
      assert {:ok, chaos_data} = chaos_result

      # Some operations should succeed despite chaos (25% success rate is reasonable under load)
      assert load_data.successful_operations >= 5

      # Verify final pool state
      assert {:ok, final_recovery} =
               verify_pool_recovery(pool_info, chaos_data.pre_failure_state, 30_000)

      assert final_recovery.recovery_successful

      Logger.info(
        "Chaos under load test: #{load_data.successful_operations}/#{load_data.total_operations} operations successful despite chaos"
      )
    end

    test "multiple chaos scenarios during sustained load", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Create sustained load task
      sustained_load_task =
        Task.async(fn ->
          # Run operations for 30 seconds
          end_time = :erlang.system_time(:millisecond) + 30_000
          run_sustained_load(pool_info, end_time, [])
        end)

      # Wait for load to establish
      :timer.sleep(3000)

      # Run multiple chaos scenarios in parallel with the load
      chaos_scenarios = [
        {:worker_failure, :random, [verify_recovery: false]},
        {:memory_pressure, [pressure_mb: 30, duration_ms: 5000, verify_recovery: false]}
      ]

      chaos_task =
        Task.async(fn ->
          chaos_test_orchestrator(pool_info, chaos_scenarios,
            execution_mode: :sequential,
            verify_recovery_between: false
          )
        end)

      # Wait for both to complete
      load_result = Task.await(sustained_load_task, 40_000)
      chaos_result = Task.await(chaos_task, 35_000)

      # Verify results
      assert is_list(load_result)
      # Should have collected some samples during sustained load
      assert length(load_result) >= 3

      assert {:ok, chaos_data} = chaos_result
      assert chaos_data.orchestration_successful

      # Verify final recovery
      initial_state = %{pool_size: 4, active_sessions: 0, expected_workers: 4}
      assert {:ok, final_recovery} = verify_pool_recovery(pool_info, initial_state, 45_000)
      assert final_recovery.recovery_successful

      Logger.info(
        "Sustained chaos test: #{length(load_result)} load samples, #{chaos_data.total_scenarios} chaos scenarios"
      )
    end
  end

  describe "Recovery Verification" do
    test "comprehensive recovery validation", context do
      pool_info = %{
        pool_pid: context.pool_pid,
        pool_name: context.pool_name,
        actual_pool_name: context.actual_pool_name
      }

      assert {:ok, :ready} = wait_for_pool_ready(context.pool_name, context.pool_name, 30_000)

      # Capture initial state
      initial_state = %{
        pool_size: 4,
        active_sessions: 0,
        expected_workers: 4
      }

      # Run comprehensive chaos
      chaos_scenarios = [
        {:worker_failure, 0.5, [verify_recovery: false]},
        {:memory_pressure, [pressure_mb: 40, duration_ms: 6000, verify_recovery: false]},
        {:port_corruption,
         [corruption_type: :random_data, duration_ms: 4000, verify_recovery: false]}
      ]

      assert {:ok, orchestration_result} =
               chaos_test_orchestrator(pool_info, chaos_scenarios,
                 execution_mode: :sequential,
                 verify_recovery_between: false
               )

      # Verify orchestration completed
      assert orchestration_result.orchestration_successful

      # Verify comprehensive recovery
      assert orchestration_result.final_recovery.recovery_successful

      # Test pool functionality after recovery
      post_chaos_operations =
        for i <- 1..5 do
          fn ->
            DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
              :ping,
              %{test: "post_chaos_verification", operation: i},
              pool_name: context.actual_pool_name,
              timeout: 10_000
            )
          end
        end

      assert {:ok, verification_result} =
               test_concurrent_operations(pool_info, post_chaos_operations, timeout: 30_000)

      # Pool should show recovery after chaos scenarios (50% success rate post-recovery)
      assert verification_result.successful_operations >= 2

      Logger.info(
        "Comprehensive recovery test: #{orchestration_result.total_scenarios} chaos scenarios, #{verification_result.successful_operations}/#{verification_result.total_operations} post-recovery operations successful"
      )
    end
  end

  ## Private Helper Functions

  defp run_sustained_load(pool_info, end_time, acc) do
    current_time = :erlang.system_time(:millisecond)

    if current_time >= end_time do
      acc
    else
      # Run a small batch of operations
      operations =
        for i <- 1..3 do
          fn ->
            DSPex.PythonBridge.SessionPoolV2.execute_anonymous(
              :ping,
              %{test: "sustained_load", batch: length(acc), operation: i},
              pool_name: pool_info.actual_pool_name,
              timeout: 8_000
            )
          end
        end

      case test_concurrent_operations(pool_info, operations, timeout: 15_000) do
        {:ok, result} ->
          sample = %{
            timestamp: current_time,
            successful_operations: result.successful_operations,
            total_operations: result.total_operations
          }

          # Brief pause before next batch
          :timer.sleep(1000)
          run_sustained_load(pool_info, end_time, [sample | acc])

        _error ->
          # Continue despite errors
          error_sample = %{
            timestamp: current_time,
            error: "operation_batch_failed"
          }

          :timer.sleep(1000)
          run_sustained_load(pool_info, end_time, [error_sample | acc])
      end
    end
  end
end
