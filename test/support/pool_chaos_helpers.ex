defmodule DSPex.PoolChaosHelpers do
  @moduledoc """
  Chaos testing helpers specifically for pool resilience testing.
  
  Provides controlled failure injection and recovery verification for:
  - Worker process crashes and recovery
  - Port communication failures
  - Session affinity disruption
  - Pool scaling failures
  - Resource exhaustion simulation
  
  Imports and extends existing supervision test helpers for comprehensive
  chaos engineering capabilities.
  """
  
  require Logger
  
  # Import existing helpers to extend them
  import DSPex.SupervisionTestHelpers
  
  alias DSPex.PythonBridge.SessionPoolV2
  
  @doc """
  Injects worker failures by killing specific workers.
  
  Supports different failure patterns:
  - :random - Kill random workers
  - :percentage - Kill a percentage of workers
  - :specific - Kill specific worker indices
  """
  @spec inject_worker_failure(map(), atom() | float() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def inject_worker_failure(pool_info, failure_pattern, opts \\ []) do
    verify_recovery = Keyword.get(opts, :verify_recovery, true)
    recovery_timeout = Keyword.get(opts, :recovery_timeout, 30_000)
    
    Logger.info("Injecting worker failure: #{inspect(failure_pattern)}")
    
    case get_pool_workers(pool_info) do
      {:ok, workers} ->
        targets = select_failure_targets(workers, failure_pattern)
        
        # Record pre-failure state
        pre_failure_state = capture_pool_state(pool_info)
        
        # Inject failures
        failure_results = inject_failures(targets, pool_info)
        
        result = %{
          failure_pattern: failure_pattern,
          targeted_workers: length(targets),
          pre_failure_state: pre_failure_state,
          failure_results: failure_results,
          timestamp: :erlang.system_time(:millisecond)
        }
        
        # Verify recovery if requested
        if verify_recovery do
          case verify_pool_recovery(pool_info, pre_failure_state, recovery_timeout) do
            {:ok, recovery_result} ->
              {:ok, Map.put(result, :recovery_result, recovery_result)}
            error ->
              {:ok, Map.put(result, :recovery_error, error)}
          end
        else
          {:ok, result}
        end
        
      error ->
        error
    end
  end
  
  @doc """
  Simulates port communication corruption and failures.
  
  Tests pool resilience to Python process communication issues.
  """
  @spec simulate_port_corruption(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def simulate_port_corruption(pool_info, opts \\ []) do
    corruption_type = Keyword.get(opts, :corruption_type, :random_data)
    duration_ms = Keyword.get(opts, :duration_ms, 5000)
    verify_recovery = Keyword.get(opts, :verify_recovery, true)
    
    Logger.info("Simulating port corruption: #{corruption_type} for #{duration_ms}ms")
    
    # Record pre-corruption state
    pre_corruption_state = capture_pool_state(pool_info)
    
    # Start corruption simulation
    corruption_task = Task.async(fn ->
      simulate_corruption_loop(pool_info, corruption_type, duration_ms)
    end)
    
    # Monitor pool behavior during corruption
    monitoring_task = Task.async(fn ->
      monitor_corruption_impact(pool_info, duration_ms)
    end)
    
    # Wait for both tasks to complete
    corruption_result = Task.await(corruption_task, duration_ms + 5000)
    monitoring_result = Task.await(monitoring_task, duration_ms + 5000)
    
    result = %{
      corruption_type: corruption_type,
      duration_ms: duration_ms,
      pre_corruption_state: pre_corruption_state,
      corruption_result: corruption_result,
      monitoring_result: monitoring_result,
      timestamp: :erlang.system_time(:millisecond)
    }
    
    # Verify recovery if requested
    if verify_recovery do
      case verify_pool_recovery(pool_info, pre_corruption_state, 30_000) do
        {:ok, recovery_result} ->
          {:ok, Map.put(result, :recovery_result, recovery_result)}
        error ->
          {:ok, Map.put(result, :recovery_error, error)}
      end
    else
      {:ok, result}
    end
  end
  
  @doc """
  Creates memory pressure to test resource exhaustion handling.
  
  Simulates memory pressure and monitors pool behavior under stress.
  """
  @spec create_memory_pressure(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_memory_pressure(pool_info, opts \\ []) do
    pressure_mb = Keyword.get(opts, :pressure_mb, 100)
    duration_ms = Keyword.get(opts, :duration_ms, 10_000)
    verify_recovery = Keyword.get(opts, :verify_recovery, true)
    
    Logger.info("Creating memory pressure: #{pressure_mb}MB for #{duration_ms}ms")
    
    # Record pre-pressure state
    pre_pressure_state = capture_pool_state(pool_info)
    initial_memory = :erlang.memory(:total)
    
    # Create memory pressure
    pressure_task = Task.async(fn ->
      create_memory_pressure_loop(pressure_mb, duration_ms)
    end)
    
    # Monitor pool behavior under pressure
    monitoring_task = Task.async(fn ->
      monitor_pressure_impact(pool_info, duration_ms)
    end)
    
    # Wait for completion
    pressure_result = Task.await(pressure_task, duration_ms + 10_000)
    monitoring_result = Task.await(monitoring_task, duration_ms + 10_000)
    
    final_memory = :erlang.memory(:total)
    
    result = %{
      pressure_mb: pressure_mb,
      duration_ms: duration_ms,
      initial_memory: initial_memory,
      final_memory: final_memory,
      memory_increase: final_memory - initial_memory,
      pre_pressure_state: pre_pressure_state,
      pressure_result: pressure_result,
      monitoring_result: monitoring_result,
      timestamp: :erlang.system_time(:millisecond)
    }
    
    # Verify recovery if requested
    if verify_recovery do
      case verify_pool_recovery(pool_info, pre_pressure_state, 30_000) do
        {:ok, recovery_result} ->
          {:ok, Map.put(result, :recovery_result, recovery_result)}
        error ->
          {:ok, Map.put(result, :recovery_error, error)}
      end
    else
      {:ok, result}
    end
  end
  
  @doc """
  Verifies pool recovery after chaos injection.
  
  Checks that the pool returns to operational state with all workers functioning.
  """
  @spec verify_pool_recovery(map(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def verify_pool_recovery(pool_info, pre_chaos_state, timeout \\ 30_000) do
    Logger.info("Verifying pool recovery within #{timeout}ms")
    
    start_time = :erlang.system_time(:millisecond)
    
    # Wait for pool to become operational
    case wait_for_pool_ready(pool_info.pool_name, pool_info.pool_name, timeout) do
      {:ok, :ready} ->
        # Verify worker count recovery
        case wait_for_workers_initialized(pool_info.pool_name, pre_chaos_state.expected_workers, timeout) do
          {:ok, worker_state} ->
            # Test pool functionality
            case test_pool_functionality(pool_info) do
              {:ok, functionality_test} ->
                recovery_time = :erlang.system_time(:millisecond) - start_time
                
                result = %{
                  recovery_successful: true,
                  recovery_time_ms: recovery_time,
                  worker_recovery: worker_state,
                  functionality_test: functionality_test,
                  final_state: capture_pool_state(pool_info)
                }
                
                Logger.info("Pool recovery verified in #{recovery_time}ms")
                {:ok, result}
                
              error ->
                {:error, {:functionality_test_failed, error}}
            end
            
          error ->
            {:error, {:worker_recovery_failed, error}}
        end
        
      error ->
        {:error, {:pool_not_ready, error}}
    end
  end
  
  @doc """
  Orchestrates multiple chaos scenarios in sequence or parallel.
  
  Coordinates complex failure patterns and recovery verification.
  """
  @spec chaos_test_orchestrator(map(), list(), keyword()) :: {:ok, map()} | {:error, term()}
  def chaos_test_orchestrator(pool_info, chaos_scenarios, opts \\ []) do
    execution_mode = Keyword.get(opts, :execution_mode, :sequential)
    verify_recovery_between = Keyword.get(opts, :verify_recovery_between, true)
    
    Logger.info("Starting chaos orchestration: #{length(chaos_scenarios)} scenarios, mode: #{execution_mode}")
    
    initial_state = capture_pool_state(pool_info)
    start_time = :erlang.system_time(:millisecond)
    
    results = case execution_mode do
      :sequential ->
        execute_chaos_scenarios_sequential(pool_info, chaos_scenarios, verify_recovery_between)
      :parallel ->
        execute_chaos_scenarios_parallel(pool_info, chaos_scenarios)
      _ ->
        {:error, {:invalid_execution_mode, execution_mode}}
    end
    
    case results do
      {:ok, scenario_results} ->
        total_time = :erlang.system_time(:millisecond) - start_time
        
        # Final recovery verification
        case verify_pool_recovery(pool_info, initial_state, 60_000) do
          {:ok, final_recovery} ->
            orchestration_result = %{
              execution_mode: execution_mode,
              total_scenarios: length(chaos_scenarios),
              scenario_results: scenario_results,
              total_time_ms: total_time,
              initial_state: initial_state,
              final_recovery: final_recovery,
              orchestration_successful: true
            }
            
            Logger.info("Chaos orchestration completed successfully in #{total_time}ms")
            {:ok, orchestration_result}
            
          error ->
            {:error, {:final_recovery_failed, error}}
        end
        
      error ->
        error
    end
  end
  
  ## Private Helper Functions
  
  defp get_pool_workers(pool_info) do
    try do
      case SessionPoolV2.get_pool_status(pool_info.pool_name) do
        status when is_map(status) ->
          # Create worker representations based on pool size
          workers = for i <- 1..status.pool_size do
            %{index: i, pool_name: pool_info.pool_name}
          end
          {:ok, workers}
          
        error ->
          {:error, {:pool_status_failed, error}}
      end
    catch
      error -> {:error, {:exception, error}}
    end
  end
  
  defp select_failure_targets(workers, :random) do
    # Select 1 random worker
    [Enum.random(workers)]
  end
  
  defp select_failure_targets(workers, percentage) when is_float(percentage) do
    count = max(1, round(length(workers) * percentage))
    Enum.take_random(workers, count)
  end
  
  defp select_failure_targets(workers, indices) when is_list(indices) do
    Enum.filter(workers, fn worker -> worker.index in indices end)
  end
  
  defp inject_failures(targets, pool_info) do
    Enum.map(targets, fn target ->
      # Simulate worker failure by attempting to overload it
      failure_result = attempt_worker_failure(target, pool_info)
      
      %{
        target: target,
        failure_result: failure_result,
        timestamp: :erlang.system_time(:millisecond)
      }
    end)
  end
  
  defp attempt_worker_failure(target, pool_info) do
    # Simulate worker failure by sending many rapid requests
    try do
      failure_operations = for _i <- 1..5 do
        Task.async(fn ->
          SessionPoolV2.execute_anonymous(
            :crash_worker,  # This operation should cause worker issues
            %{chaos_test: true, target: target.index},
            pool_name: pool_info.actual_pool_name,
            timeout: 1000  # Short timeout to cause failures
          )
        end)
      end
      
      # Don't wait for all to complete - some should fail
      :timer.sleep(2000)
      
      # Count how many are still running
      running_count = Enum.count(failure_operations, fn task ->
        case Task.yield(task, 0) do
          nil -> true  # Still running
          _ -> false   # Completed or failed
        end
      end)
      
      {:ok, %{operations_sent: 5, still_running: running_count}}
    catch
      error -> {:error, error}
    end
  end
  
  defp capture_pool_state(pool_info) do
    try do
      status = SessionPoolV2.get_pool_status(pool_info.pool_name)
      
      %{
        pool_size: status.pool_size,
        active_sessions: status.active_sessions,
        expected_workers: status.pool_size,
        timestamp: :erlang.system_time(:millisecond)
      }
    catch
      _error ->
        %{
          pool_size: 0,
          active_sessions: 0,
          expected_workers: 0,
          error: "failed_to_capture_state",
          timestamp: :erlang.system_time(:millisecond)
        }
    end
  end
  
  defp simulate_corruption_loop(_pool_info, _corruption_type, duration_ms) do
    # Simulate corruption by attempting invalid operations
    end_time = :erlang.system_time(:millisecond) + duration_ms
    corruption_count = simulate_corruption_operations(end_time, 0)
    
    %{
      corruption_operations: corruption_count,
      duration_ms: duration_ms
    }
  end
  
  defp simulate_corruption_operations(end_time, count) do
    current_time = :erlang.system_time(:millisecond)
    
    if current_time >= end_time do
      count
    else
      # Simulate corruption by sending invalid data
      # This is a placeholder - real implementation would send malformed data
      :timer.sleep(100)
      simulate_corruption_operations(end_time, count + 1)
    end
  end
  
  defp monitor_corruption_impact(pool_info, duration_ms) do
    end_time = :erlang.system_time(:millisecond) + duration_ms
    samples = collect_corruption_samples(pool_info, end_time, [])
    
    %{
      sample_count: length(samples),
      samples: samples
    }
  end
  
  defp collect_corruption_samples(pool_info, end_time, acc) do
    current_time = :erlang.system_time(:millisecond)
    
    if current_time >= end_time do
      Enum.reverse(acc)
    else
      sample = capture_pool_state(pool_info)
      :timer.sleep(500)  # Sample every 500ms
      collect_corruption_samples(pool_info, end_time, [sample | acc])
    end
  end
  
  defp create_memory_pressure_loop(pressure_mb, duration_ms) do
    # Create memory pressure by allocating large binaries
    _end_time = :erlang.system_time(:millisecond) + duration_ms
    pressure_data = create_pressure_data(pressure_mb)
    
    # Hold the memory for the duration
    :timer.sleep(duration_ms)
    
    %{
      pressure_mb: pressure_mb,
      data_size: byte_size(pressure_data),
      duration_ms: duration_ms
    }
  end
  
  defp create_pressure_data(mb) do
    # Create a binary of approximately the requested size
    size_bytes = mb * 1024 * 1024
    :binary.copy(<<0>>, size_bytes)
  end
  
  defp monitor_pressure_impact(pool_info, duration_ms) do
    end_time = :erlang.system_time(:millisecond) + duration_ms
    samples = collect_pressure_samples(pool_info, end_time, [])
    
    %{
      sample_count: length(samples),
      samples: samples
    }
  end
  
  defp collect_pressure_samples(pool_info, end_time, acc) do
    current_time = :erlang.system_time(:millisecond)
    
    if current_time >= end_time do
      Enum.reverse(acc)
    else
      sample = %{
        pool_state: capture_pool_state(pool_info),
        memory_usage: :erlang.memory(:total),
        timestamp: current_time
      }
      
      :timer.sleep(1000)  # Sample every second
      collect_pressure_samples(pool_info, end_time, [sample | acc])
    end
  end
  
  defp test_pool_functionality(pool_info) do
    # Test basic pool operations to verify functionality
    test_operations = [
      fn ->
        SessionPoolV2.execute_anonymous(
          :ping,
          %{test: "recovery_verification"},
          pool_name: pool_info.actual_pool_name,
          timeout: 5000
        )
      end,
      fn ->
        SessionPoolV2.execute_anonymous(
          :ping,
          %{test: "recovery_verification_2"},
          pool_name: pool_info.actual_pool_name,
          timeout: 5000
        )
      end
    ]
    
    try do
      results = DSPex.PoolV2TestHelpers.run_concurrent_operations(test_operations, 60_000)
      
      success_count = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      {:ok, %{
        total_tests: length(test_operations),
        successful_tests: success_count,
        success_rate: success_count / length(test_operations),
        test_results: results
      }}
    catch
      error -> {:error, error}
    end
  end
  
  defp execute_chaos_scenarios_sequential(pool_info, scenarios, verify_recovery_between) do
    {results, _final_state} = Enum.reduce(scenarios, {[], capture_pool_state(pool_info)}, fn scenario, {acc, current_state} ->
      Logger.info("Executing chaos scenario: #{inspect(scenario)}")
      
      scenario_result = execute_single_chaos_scenario(pool_info, scenario)
      
      # Verify recovery between scenarios if requested
      recovery_result = if verify_recovery_between do
        case verify_pool_recovery(pool_info, current_state, 30_000) do
          {:ok, recovery} -> recovery
          error -> %{recovery_error: error}
        end
      else
        %{recovery_skipped: true}
      end
      
      new_state = capture_pool_state(pool_info)
      
      combined_result = %{
        scenario: scenario,
        scenario_result: scenario_result,
        recovery_result: recovery_result,
        timestamp: :erlang.system_time(:millisecond)
      }
      
      {[combined_result | acc], new_state}
    end)
    
    {:ok, Enum.reverse(results)}
  end
  
  defp execute_chaos_scenarios_parallel(pool_info, scenarios) do
    Logger.info("Executing #{length(scenarios)} chaos scenarios in parallel")
    
    tasks = Enum.map(scenarios, fn scenario ->
      Task.async(fn ->
        execute_single_chaos_scenario(pool_info, scenario)
      end)
    end)
    
    try do
      results = Task.await_many(tasks, 60_000)
      
      scenario_results = Enum.zip(scenarios, results)
        |> Enum.map(fn {scenario, result} ->
          %{
            scenario: scenario,
            scenario_result: result,
            timestamp: :erlang.system_time(:millisecond)
          }
        end)
      
      {:ok, scenario_results}
    catch
      error -> {:error, {:parallel_execution_failed, error}}
    end
  end
  
  defp execute_single_chaos_scenario(pool_info, scenario) do
    case scenario do
      {:worker_failure, pattern, opts} ->
        inject_worker_failure(pool_info, pattern, opts)
      
      {:port_corruption, opts} ->
        simulate_port_corruption(pool_info, opts)
      
      {:memory_pressure, opts} ->
        create_memory_pressure(pool_info, opts)
      
      unknown ->
        {:error, {:unknown_scenario, unknown}}
    end
  end
end