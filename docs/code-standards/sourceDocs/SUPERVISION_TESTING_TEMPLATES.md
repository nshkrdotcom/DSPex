# Supervision Testing Templates and Future Patterns

**Document Version**: 1.0  
**Date**: 2025-07-02  
**Purpose**: Templates, patterns, and guidelines for implementing new supervision tests and extending the testing framework

---

## Table of Contents

1. [Test Templates](#test-templates)
2. [Service Integration Patterns](#service-integration-patterns)
3. [Advanced Testing Patterns](#advanced-testing-patterns)
4. [Extension Guidelines](#extension-guidelines)
5. [Performance Testing Templates](#performance-testing-templates)
6. [CI/CD Integration Patterns](#cicd-integration-patterns)
7. [Future Enhancement Roadmap](#future-enhancement-roadmap)

---

## Test Templates

### 1. Basic Service Crash Recovery Test Template

```elixir
defmodule MyApp.ServiceNameSupervisionTest do
  @moduledoc """
  Supervision crash recovery tests for MyApp.ServiceName.
  
  Tests verify that the service properly restarts after crashes,
  maintains functionality, and integrates correctly with the supervision tree.
  """
  
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag timeout: 30_000
  
  describe "MyApp.ServiceName crash recovery" do
    test "service restarts after crash and maintains functionality", 
         %{supervision_tree: sup_tree} do
      # 1. Get service from isolated supervision tree
      {:ok, service_pid} = get_service(sup_tree, :my_service_name)
      assert is_pid(service_pid)
      
      # 2. Test functionality before crash
      result = call_service(sup_tree, :my_service_name, :get_status)
      assert result == :ok  # or whatever expected result
      
      # 3. Kill the service
      Process.exit(service_pid, :kill)
      
      # 4. Wait for restart
      {:ok, new_pid} = wait_for_service_restart(sup_tree, :my_service_name, service_pid)
      
      # 5. Verify restart
      assert new_pid != service_pid
      assert Process.alive?(new_pid)
      
      # 6. Test functionality after restart
      new_result = call_service(sup_tree, :my_service_name, :get_status)
      assert new_result == :ok
    end
    
    test "service handles multiple rapid crashes gracefully",
         %{supervision_tree: sup_tree} do
      # Test rapid crash/restart cycles
      for i <- 1..3 do
        {:ok, service_pid} = get_service(sup_tree, :my_service_name)
        Process.exit(service_pid, :kill)
        
        {:ok, new_pid} = wait_for_service_restart(sup_tree, :my_service_name, service_pid)
        assert new_pid != service_pid
        
        # Verify service is functional after each restart
        result = call_service(sup_tree, :my_service_name, :get_status)
        assert result == :ok
      end
    end
    
    test "service state recovery after restart", %{supervision_tree: sup_tree} do
      # 1. Set up initial state
      :ok = call_service(sup_tree, :my_service_name, {:configure, %{setting: "test_value"}})
      
      # 2. Verify initial state
      {:ok, config} = call_service(sup_tree, :my_service_name, :get_config)
      assert config.setting == "test_value"
      
      # 3. Crash the service
      {:ok, service_pid} = get_service(sup_tree, :my_service_name)
      Process.exit(service_pid, :kill)
      
      # 4. Wait for restart
      {:ok, _new_pid} = wait_for_service_restart(sup_tree, :my_service_name, service_pid)
      
      # 5. Verify state recovery (if persistent) or reset (if stateless)
      {:ok, new_config} = call_service(sup_tree, :my_service_name, :get_config)
      # Adjust assertion based on whether service maintains state
      assert new_config.setting == "default_value"  # For stateless services
      # OR: assert new_config.setting == "test_value"  # For persistent services
    end
  end
  
  describe "Resource management" do
    test "no resource leaks after service restarts", %{supervision_tree: sup_tree} do
      initial_count = :erlang.system_info(:process_count)
      
      # Multiple crash/restart cycles
      for _i <- 1..5 do
        {:ok, service_pid} = get_service(sup_tree, :my_service_name)
        Process.exit(service_pid, :kill)
        {:ok, _new_pid} = wait_for_service_restart(sup_tree, :my_service_name, service_pid)
      end
      
      # Allow system to stabilize
      Process.sleep(1000)
      
      final_count = :erlang.system_info(:process_count)
      assert final_count - initial_count < 20,
             "Process leak detected: #{initial_count} -> #{final_count}"
    end
  end
end
```

### 2. Complex Service Integration Test Template

```elixir
defmodule MyApp.ServiceIntegrationSupervisionTest do
  @moduledoc """
  Integration supervision tests for multiple interdependent services.
  
  Tests verify that services properly handle dependencies during
  restart scenarios and maintain system consistency.
  """
  
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag timeout: 30_000
  
  describe "Service dependency management" do
    test "dependent services restart correctly with rest_for_one",
         %{supervision_tree: sup_tree} do
      # Monitor all relevant services
      monitors = monitor_all_services(sup_tree)
      
      # Get the service to crash (adjust based on your supervision order)
      {crash_service_pid, _} = monitors[:service_to_crash]
      
      # Kill the service
      Process.exit(crash_service_pid, :kill)
      
      # Verify rest_for_one cascade behavior
      verify_rest_for_one_cascade(monitors, :service_to_crash)
      
      # Verify dependent services restarted correctly
      wait_for_services_restart(sup_tree, %{
        dependent_service_1: monitors[:dependent_service_1] |> elem(0),
        dependent_service_2: monitors[:dependent_service_2] |> elem(0)
      })
      
      # Test integration functionality after restart
      result = call_service(sup_tree, :dependent_service_1, :test_dependency)
      assert result == :ok
    end
    
    test "system maintains consistency during cascading failures",
         %{supervision_tree: sup_tree} do
      # Set up cross-service state
      :ok = call_service(sup_tree, :service_a, {:register, :key1, "value1"})
      :ok = call_service(sup_tree, :service_b, {:register, :key2, "value2"})
      
      # Verify initial state
      {:ok, value1} = call_service(sup_tree, :service_a, {:get, :key1})
      {:ok, value2} = call_service(sup_tree, :service_b, {:get, :key2})
      assert value1 == "value1"
      assert value2 == "value2"
      
      # Cause cascading failure
      {:ok, service_a_pid} = get_service(sup_tree, :service_a)
      Process.exit(service_a_pid, :kill)
      
      # Wait for cascade to complete
      {:ok, _new_a_pid} = wait_for_service_restart(sup_tree, :service_a, service_a_pid)
      {:ok, _new_b_pid} = wait_for_service_restart(sup_tree, :service_b, 
        call_service(sup_tree, :service_b, :get_pid))
      
      # Verify system consistency (adjust based on your requirements)
      {:ok, new_value1} = call_service(sup_tree, :service_a, {:get, :key1})
      {:ok, new_value2} = call_service(sup_tree, :service_b, {:get, :key2})
      
      # State may be reset or recovered depending on design
      assert new_value1 == nil  # For stateless reset
      assert new_value2 == nil  # For stateless reset
    end
  end
end
```

### 3. Performance and Load Testing Template

```elixir
defmodule MyApp.ServicePerformanceSupervisionTest do
  @moduledoc """
  Performance-focused supervision tests.
  
  Tests verify that supervision behavior performs adequately under
  various load conditions and stress scenarios.
  """
  
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag :performance
  @moduletag timeout: 60_000
  
  describe "Performance under load" do
    test "restart time remains consistent under high load",
         %{supervision_tree: sup_tree} do
      # Measure restart times under various conditions
      restart_times = []
      
      # Baseline measurement
      baseline_times = measure_restart_times(sup_tree, :my_service, 5)
      baseline_avg = Enum.sum(baseline_times) / length(baseline_times)
      
      # Create background load
      load_tasks = create_background_load(sup_tree, 10)
      
      # Measure restart times under load
      load_times = measure_restart_times(sup_tree, :my_service, 5)
      load_avg = Enum.sum(load_times) / length(load_times)
      
      # Clean up background load
      Enum.each(load_tasks, &Task.shutdown/1)
      
      # Performance should not degrade significantly
      degradation = (load_avg - baseline_avg) / baseline_avg
      assert degradation < 0.50,  # Allow up to 50% degradation
             "Restart time degraded too much: #{baseline_avg}ms -> #{load_avg}ms"
    end
    
    test "memory usage remains stable during restart cycles",
         %{supervision_tree: sup_tree} do
      initial_memory = :erlang.memory(:total)
      
      # Perform many restart cycles
      for _i <- 1..20 do
        {:ok, service_pid} = get_service(sup_tree, :my_service)
        Process.exit(service_pid, :kill)
        {:ok, _new_pid} = wait_for_service_restart(sup_tree, :my_service, service_pid)
        
        # Trigger garbage collection periodically
        if rem(_i, 5) == 0, do: :erlang.garbage_collect()
      end
      
      # Allow memory stabilization
      :erlang.garbage_collect()
      Process.sleep(2000)
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be minimal (adjust threshold as needed)
      assert memory_growth < 10_000_000,  # 10MB
             "Excessive memory growth: #{initial_memory} -> #{final_memory}"
    end
  end
  
  # Helper functions for performance testing
  defp measure_restart_times(sup_tree, service_name, count) do
    for _i <- 1..count do
      {:ok, service_pid} = get_service(sup_tree, service_name)
      
      start_time = :erlang.monotonic_time(:millisecond)
      Process.exit(service_pid, :kill)
      
      {:ok, _new_pid} = wait_for_service_restart(sup_tree, service_name, service_pid)
      end_time = :erlang.monotonic_time(:millisecond)
      
      end_time - start_time
    end
  end
  
  defp create_background_load(sup_tree, task_count) do
    for _i <- 1..task_count do
      Task.async(fn ->
        # Create load appropriate for your services
        for _j <- 1..100 do
          call_service(sup_tree, :my_service, :get_status)
          Process.sleep(10)
        end
      end)
    end
  end
end
```

---

## Service Integration Patterns

### 1. Adding New Service to Supervision Testing

When adding a new service to the supervision testing framework:

#### Step 1: Update Service Mappings

```elixir
# In test/support/supervision_test_helpers.ex
@service_modules %{
  # Existing services...
  task_pool_manager: JidoFoundation.TaskPoolManager,
  system_command_manager: JidoFoundation.SystemCommandManager,
  coordination_manager: JidoFoundation.CoordinationManager,
  scheduler_manager: JidoFoundation.SchedulerManager,
  
  # Add your new service
  my_new_service: JidoFoundation.MyNewService
}

@supervision_order [
  # Existing order...
  :scheduler_manager,
  :task_pool_manager,
  :system_command_manager,
  :coordination_manager,
  
  # Add your service in the correct position
  :my_new_service
]
```

#### Step 2: Update Type Specifications

```elixir
# In test/support/supervision_test_helpers.ex
@type service_name :: 
        :task_pool_manager 
        | :system_command_manager 
        | :coordination_manager 
        | :scheduler_manager
        | :my_new_service  # Add your service
```

#### Step 3: Create Test Service Implementation

```elixir
# In test/support/foundation_test_services.ex (if it doesn't exist, create it)
defmodule Foundation.TestServices.MyNewService do
  @moduledoc """
  Test double for JidoFoundation.MyNewService in isolated supervision testing.
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    registry = Keyword.get(opts, :registry, nil)
    
    GenServer.start_link(__MODULE__, {opts, registry}, name: name)
  end
  
  def init({opts, registry}) do
    # Register with test registry if provided
    if registry do
      Registry.register(registry, {:service, JidoFoundation.MyNewService}, %{test_instance: true})
    end
    
    # Initialize service state (minimal for testing)
    {:ok, %{config: %{}, started_at: DateTime.utc_now()}}
  end
  
  # Implement minimal interface needed for testing
  def handle_call(:get_status, _from, state) do
    {:reply, :ok, state}
  end
  
  def handle_call(:get_config, _from, state) do
    {:reply, {:ok, state.config}, state}
  end
  
  def handle_call({:configure, config}, _from, state) do
    new_state = Map.put(state, :config, config)
    {:reply, :ok, new_state}
  end
  
  # Handle other calls as needed...
end
```

#### Step 4: Update Supervision Setup

```elixir
# In test/support/supervision_test_setup.ex
@core_services [
  # Existing services...
  Foundation.TestServices.SchedulerManager,
  Foundation.TestServices.TaskPoolManager,
  Foundation.TestServices.SystemCommandManager,
  Foundation.TestServices.CoordinationManager,
  
  # Add your test service
  Foundation.TestServices.MyNewService
]

# Update the isolated supervisor children list
defp start_isolated_jido_supervisor(supervisor_name, registry_name) do
  children = [
    # ... existing children ...
    
    # Add your service
    {Foundation.TestServices.MyNewService,
     name: :"#{supervisor_name}_my_new_service", registry: registry_name}
  ]
  
  # ... rest of function
end
```

### 2. Custom Service Discovery Pattern

For services that need special discovery mechanisms:

```elixir
defmodule MyApp.CustomServiceDiscovery do
  @moduledoc """
  Custom service discovery for specialized services.
  """
  
  import Foundation.SupervisionTestHelpers
  
  def get_custom_service(sup_tree, service_identifier) do
    # Custom lookup logic
    case Registry.lookup(sup_tree.registry, {:custom_service, service_identifier}) do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      [] -> {:error, :custom_service_not_found}
    end
  end
  
  def wait_for_custom_service_restart(sup_tree, service_identifier, old_pid, timeout \\ 5000) do
    wait_for(
      fn ->
        case get_custom_service(sup_tree, service_identifier) do
          {:ok, new_pid} when new_pid != old_pid -> {:ok, new_pid}
          _ -> nil
        end
      end,
      timeout
    )
  end
end
```

---

## Advanced Testing Patterns

### 1. Property-Based Supervision Testing

```elixir
defmodule MyApp.PropertyBasedSupervisionTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  use ExUnitProperties
  
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag :property_based
  
  property "services always restart after any kind of crash", %{supervision_tree: sup_tree} do
    check all service_name <- member_of(get_supported_services()),
              kill_signal <- member_of([:kill, :shutdown, :normal, {:shutdown, :reason}]),
              max_runs: 25 do
      
      # Get service before crash
      {:ok, original_pid} = get_service(sup_tree, service_name)
      
      # Crash it with various signals
      Process.exit(original_pid, kill_signal)
      
      # Should always restart
      {:ok, new_pid} = wait_for_service_restart(sup_tree, service_name, original_pid, 10_000)
      
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
      
      # Should be functional after restart
      case call_service(sup_tree, service_name, :get_status, [], 5000) do
        {:error, _} -> :ok  # Service may not implement get_status
        result -> assert result != nil
      end
    end
  end
  
  property "supervision trees are always consistent", %{supervision_tree: sup_tree} do
    check all services_to_crash <- uniq_list_of(member_of(get_supported_services()), 
                                               min_length: 1, max_length: 3),
              max_runs: 15 do
      
      # Get initial state
      initial_pids = for service <- services_to_crash do
        {:ok, pid} = get_service(sup_tree, service)
        {service, pid}
      end
      
      # Crash all services simultaneously
      for {service, pid} <- initial_pids do
        Process.exit(pid, :kill)
      end
      
      # Wait for all to restart
      for {service, old_pid} <- initial_pids do
        {:ok, new_pid} = wait_for_service_restart(sup_tree, service, old_pid, 10_000)
        assert new_pid != old_pid
      end
      
      # Verify supervision tree consistency
      stats = Foundation.SupervisionTestSetup.get_supervision_stats(sup_tree)
      assert stats.supervisor_alive == true
      assert stats.registered_services >= length(services_to_crash)
    end
  end
end
```

### 2. Chaos Engineering Pattern

```elixir
defmodule MyApp.ChaosSupervisionTest do
  @moduledoc """
  Chaos engineering tests for supervision resilience.
  """
  
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag :chaos
  @moduletag timeout: 120_000
  
  describe "Chaos testing" do
    test "system survives random service crashes", %{supervision_tree: sup_tree} do
      # Run chaos for 30 seconds
      end_time = System.monotonic_time(:millisecond) + 30_000
      
      chaos_task = Task.async(fn ->
        run_chaos_loop(sup_tree, end_time)
      end)
      
      # Monitor system health during chaos
      health_task = Task.async(fn ->
        monitor_system_health(sup_tree, end_time)
      end)
      
      # Wait for both tasks to complete
      chaos_events = Task.await(chaos_task, 35_000)
      health_results = Task.await(health_task, 35_000)
      
      # Verify system survived
      assert length(chaos_events) > 0, "No chaos events occurred"
      assert Enum.all?(health_results, & &1.healthy), "System became unhealthy"
      
      # Verify final state
      final_stats = Foundation.SupervisionTestSetup.get_supervision_stats(sup_tree)
      assert final_stats.supervisor_alive == true
    end
  end
  
  defp run_chaos_loop(sup_tree, end_time) do
    run_chaos_loop(sup_tree, end_time, [])
  end
  
  defp run_chaos_loop(sup_tree, end_time, events) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time >= end_time do
      events
    else
      # Random chaos action
      action = Enum.random([:kill_service, :overload_service, :pause])
      
      event = case action do
        :kill_service ->
          service = Enum.random(get_supported_services())
          case get_service(sup_tree, service) do
            {:ok, pid} ->
              Process.exit(pid, :kill)
              %{action: :kill, service: service, time: current_time}
            _ ->
              %{action: :kill_failed, service: service, time: current_time}
          end
          
        :overload_service ->
          service = Enum.random(get_supported_services())
          # Send many concurrent requests
          for _i <- 1..10 do
            spawn(fn ->
              call_service(sup_tree, service, :get_status, [], 100)
            end)
          end
          %{action: :overload, service: service, time: current_time}
          
        :pause ->
          Process.sleep(Enum.random(100..500))
          %{action: :pause, time: current_time}
      end
      
      Process.sleep(Enum.random(200..1000))
      run_chaos_loop(sup_tree, end_time, [event | events])
    end
  end
  
  defp monitor_system_health(sup_tree, end_time) do
    monitor_system_health(sup_tree, end_time, [])
  end
  
  defp monitor_system_health(sup_tree, end_time, results) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time >= end_time do
      results
    else
      health_check = %{
        time: current_time,
        healthy: system_healthy?(sup_tree)
      }
      
      Process.sleep(1000)  # Check every second
      monitor_system_health(sup_tree, end_time, [health_check | results])
    end
  end
  
  defp system_healthy?(sup_tree) do
    try do
      stats = Foundation.SupervisionTestSetup.get_supervision_stats(sup_tree)
      stats.supervisor_alive && stats.registered_services > 0
    rescue
      _ -> false
    end
  end
end
```

---

## Extension Guidelines

### 1. Creating New Test Modes

To create a new testing mode for `Foundation.UnifiedTestFoundation`:

```elixir
# In test/support/unified_test_foundation.ex

defmacro __using__(mode) when mode == :my_custom_testing do
  quote do
    use ExUnit.Case, async: false  # or true if safe
    
    import Foundation.AsyncTestHelpers
    import MyApp.CustomTestHelpers  # Your custom helpers
    
    setup do
      MyApp.CustomTestSetup.create_custom_context()
    end
  end
end
```

### 2. Custom Test Helper Modules

Structure for creating specialized test helpers:

```elixir
defmodule MyApp.CustomTestHelpers do
  @moduledoc """
  Custom test helpers for specialized testing scenarios.
  """
  
  import Foundation.AsyncTestHelpers
  import ExUnit.Assertions
  
  @type custom_context :: %{
    custom_field: term(),
    # ... other fields
  }
  
  @spec custom_helper_function(custom_context(), term()) :: term()
  def custom_helper_function(context, params) do
    # Implementation
  end
  
  # ... other helper functions
end
```

### 3. Test Setup Modules

Pattern for creating custom test setup:

```elixir
defmodule MyApp.CustomTestSetup do
  @moduledoc """
  Custom test setup for specialized testing scenarios.
  """
  
  import Foundation.AsyncTestHelpers
  import ExUnit.Callbacks
  
  @spec create_custom_context() :: %{custom_context: map()}
  def create_custom_context do
    # Setup logic
    custom_context = %{
      # ... context fields
    }
    
    on_exit(fn ->
      cleanup_custom_context(custom_context)
    end)
    
    %{custom_context: custom_context}
  end
  
  @spec cleanup_custom_context(map()) :: :ok
  def cleanup_custom_context(context) do
    # Cleanup logic
    :ok
  end
end
```

---

## Performance Testing Templates

### 1. Benchmark Template

```elixir
defmodule MyApp.SupervisionBenchmarkTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag :benchmark
  @moduletag timeout: 300_000  # 5 minutes
  
  describe "Supervision performance benchmarks" do
    test "restart time benchmarks", %{supervision_tree: sup_tree} do
      services = get_supported_services()
      
      results = for service <- services do
        times = measure_restart_times(sup_tree, service, 10)
        
        %{
          service: service,
          min_time: Enum.min(times),
          max_time: Enum.max(times),
          avg_time: Enum.sum(times) / length(times),
          median_time: median(times),
          p95_time: percentile(times, 0.95),
          p99_time: percentile(times, 0.99)
        }
      end
      
      # Log results for performance tracking
      for result <- results do
        IO.puts("#{result.service}: avg=#{result.avg_time}ms, p95=#{result.p95_time}ms, p99=#{result.p99_time}ms")
      end
      
      # Assert performance requirements
      for result <- results do
        assert result.avg_time < 1000, "#{result.service} restart too slow: #{result.avg_time}ms"
        assert result.p99_time < 3000, "#{result.service} p99 restart too slow: #{result.p99_time}ms"
      end
    end
  end
  
  defp measure_restart_times(sup_tree, service, count) do
    for _i <- 1..count do
      {:ok, pid} = get_service(sup_tree, service)
      
      start_time = :erlang.monotonic_time(:microsecond)
      Process.exit(pid, :kill)
      
      {:ok, _new_pid} = wait_for_service_restart(sup_tree, service, pid)
      end_time = :erlang.monotonic_time(:microsecond)
      
      (end_time - start_time) / 1000  # Convert to milliseconds
    end
  end
  
  defp median(list) do
    sorted = Enum.sort(list)
    length = length(sorted)
    
    if rem(length, 2) == 0 do
      (Enum.at(sorted, div(length, 2) - 1) + Enum.at(sorted, div(length, 2))) / 2
    else
      Enum.at(sorted, div(length, 2))
    end
  end
  
  defp percentile(list, p) do
    sorted = Enum.sort(list)
    index = round(p * (length(sorted) - 1))
    Enum.at(sorted, index)
  end
end
```

### 2. Memory Profiling Template

```elixir
defmodule MyApp.SupervisionMemoryTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag :memory_profiling
  @moduletag timeout: 180_000
  
  describe "Memory usage profiling" do
    test "memory usage during supervision lifecycle", %{supervision_tree: sup_tree} do
      # Take initial memory snapshot
      initial_memory = memory_snapshot()
      
      # Perform typical supervision operations
      for i <- 1..50 do
        service = Enum.random(get_supported_services())
        {:ok, pid} = get_service(sup_tree, service)
        
        # Every 10 operations, crash and restart
        if rem(i, 10) == 0 do
          Process.exit(pid, :kill)
          {:ok, _new_pid} = wait_for_service_restart(sup_tree, service, pid)
        end
        
        # Take periodic snapshots
        if rem(i, 10) == 0 do
          snapshot = memory_snapshot()
          log_memory_usage(i, snapshot, initial_memory)
        end
      end
      
      # Force garbage collection and take final snapshot
      :erlang.garbage_collect()
      Process.sleep(1000)
      final_memory = memory_snapshot()
      
      # Analyze memory usage
      analyze_memory_usage(initial_memory, final_memory)
    end
  end
  
  defp memory_snapshot do
    %{
      total: :erlang.memory(:total),
      processes: :erlang.memory(:processes),
      system: :erlang.memory(:system),
      atom: :erlang.memory(:atom),
      binary: :erlang.memory(:binary),
      ets: :erlang.memory(:ets),
      process_count: :erlang.system_info(:process_count),
      ets_count: :erlang.system_info(:ets_count)
    }
  end
  
  defp log_memory_usage(iteration, current, initial) do
    growth = current.total - initial.total
    IO.puts("Iteration #{iteration}: Total memory #{current.total}, Growth: #{growth}")
  end
  
  defp analyze_memory_usage(initial, final) do
    growth_total = final.total - initial.total
    growth_processes = final.processes - initial.processes
    growth_ets = final.ets - initial.ets
    
    # Assert reasonable memory usage
    assert growth_total < 50_000_000,  # 50MB
           "Excessive total memory growth: #{growth_total}"
    assert growth_processes < 20_000_000,  # 20MB
           "Excessive process memory growth: #{growth_processes}"
    assert growth_ets < 10_000_000,  # 10MB
           "Excessive ETS memory growth: #{growth_ets}"
    
    IO.puts("Memory analysis complete:")
    IO.puts("  Total growth: #{growth_total} bytes")
    IO.puts("  Process growth: #{growth_processes} bytes")
    IO.puts("  ETS growth: #{growth_ets} bytes")
  end
end
```

---

## CI/CD Integration Patterns

### 1. GitHub Actions Integration

```yaml
# .github/workflows/supervision_tests.yml
name: Supervision Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  supervision_tests:
    name: Supervision Crash Recovery Tests
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        elixir: ['1.15.7']
        otp: ['26.1']
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}
    
    - name: Restore dependencies cache
      uses: actions/cache@v3
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
        restore-keys: ${{ runner.os }}-mix-
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Compile code
      run: mix compile --warnings-as-errors
    
    - name: Run supervision tests
      run: |
        mix test test/jido_foundation/supervision_crash_recovery_test.exs --trace
        mix test test/jido_foundation/supervision_crash_recovery_test.exs --seed 12345
        mix test test/jido_foundation/supervision_crash_recovery_test.exs --seed 67890
    
    - name: Run supervision tests with parallel execution
      run: mix test test/jido_foundation/supervision_crash_recovery_test.exs --max-cases 4
    
    - name: Run memory profiling tests
      run: mix test --only memory_profiling
    
    - name: Upload test artifacts
      if: failure()
      uses: actions/upload-artifact@v3
      with:
        name: test-logs
        path: |
          _build/test/logs/
          test_output.log
```

### 2. Performance Regression Detection

```elixir
# test/support/performance_tracker.ex
defmodule Foundation.PerformanceTracker do
  @moduledoc """
  Track and compare supervision test performance across builds.
  """
  
  @results_file "test/performance_results.json"
  
  def record_results(test_name, results) do
    existing = load_existing_results()
    
    new_entry = %{
      test: test_name,
      timestamp: DateTime.utc_now(),
      results: results,
      git_sha: get_git_sha(),
      elixir_version: System.version(),
      otp_version: System.otp_release()
    }
    
    updated = [new_entry | existing]
    save_results(updated)
  end
  
  def check_regression(test_name, current_results) do
    historical = load_existing_results()
    |> Enum.filter(&(&1.test == test_name))
    |> Enum.take(10)  # Last 10 runs
    
    if length(historical) >= 3 do
      baseline = calculate_baseline(historical)
      regression = detect_regression(baseline, current_results)
      
      if regression do
        IO.warn("Performance regression detected in #{test_name}: #{inspect(regression)}")
      end
      
      regression
    else
      nil  # Not enough data
    end
  end
  
  defp load_existing_results do
    case File.read(@results_file) do
      {:ok, content} -> Jason.decode!(content)
      {:error, _} -> []
    end
  end
  
  defp save_results(results) do
    content = Jason.encode!(results, pretty: true)
    File.write!(@results_file, content)
  end
  
  defp get_git_sha do
    case System.cmd("git", ["rev-parse", "HEAD"]) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end
  
  defp calculate_baseline(historical) do
    # Calculate averages from historical data
    %{
      avg_restart_time: historical
      |> Enum.map(&get_in(&1, [:results, :avg_restart_time]))
      |> Enum.filter(& &1)
      |> average(),
      
      avg_memory_usage: historical
      |> Enum.map(&get_in(&1, [:results, :avg_memory_usage]))
      |> Enum.filter(& &1)
      |> average()
    }
  end
  
  defp detect_regression(baseline, current) do
    regressions = []
    
    # Check restart time regression (20% threshold)
    if current.avg_restart_time > baseline.avg_restart_time * 1.2 do
      regressions = [{:restart_time_regression, 
        %{baseline: baseline.avg_restart_time, current: current.avg_restart_time}} | regressions]
    end
    
    # Check memory regression (30% threshold)
    if current.avg_memory_usage > baseline.avg_memory_usage * 1.3 do
      regressions = [{:memory_regression,
        %{baseline: baseline.avg_memory_usage, current: current.avg_memory_usage}} | regressions]
    end
    
    case regressions do
      [] -> nil
      _ -> regressions
    end
  end
  
  defp average([]), do: 0
  defp average(list), do: Enum.sum(list) / length(list)
end
```

---

## Future Enhancement Roadmap

### Phase 1: Advanced Monitoring (Q1 2025)

1. **Real-time Telemetry Integration**
   ```elixir
   # Enhanced telemetry for supervision events
   :telemetry.execute([:supervision, :service, :restart], %{
     service: service_name,
     restart_time: restart_time,
     restart_count: restart_count
   })
   ```

2. **Distributed Supervision Testing**
   ```elixir
   # Test supervision across multiple nodes
   defmodule DistributedSupervisionTest do
     use Foundation.UnifiedTestFoundation, :distributed_supervision_testing
     
     test "service failover across nodes", %{cluster: cluster} do
       # Test supervision behavior in distributed environment
     end
   end
   ```

### Phase 2: AI-Powered Testing (Q2 2025)

1. **Intelligent Chaos Generation**
   - ML-based chaos pattern generation
   - Adaptive chaos based on system behavior
   - Predictive failure scenario testing

2. **Automated Performance Optimization**
   - AI-driven supervision tuning recommendations
   - Automatic detection of optimal restart strategies
   - Dynamic timeout adjustment based on load patterns

### Phase 3: Production Integration (Q3 2025)

1. **Shadow Testing Framework**
   ```elixir
   # Run supervision tests against production traffic shadows
   defmodule ProductionShadowTest do
     use Foundation.UnifiedTestFoundation, :shadow_testing
     
     test "production workload supervision behavior" do
       # Test with real production patterns
     end
   end
   ```

2. **Continuous Supervision Validation**
   - Background supervision health monitoring
   - Real-time regression detection
   - Automated rollback triggers

### Phase 4: Advanced Patterns (Q4 2025)

1. **Multi-Language Supervision Testing**
   - Support for testing Rust NIFs supervision
   - Erlang port supervision testing
   - Cross-language supervision coordination

2. **Advanced Resource Management**
   - GPU resource supervision testing
   - Network resource supervision patterns
   - Storage supervision testing

---

## Conclusion

This template collection provides:

1. **Ready-to-use templates** for common supervision testing scenarios
2. **Extension patterns** for adding new services and test modes
3. **Advanced testing techniques** including chaos engineering and property-based testing
4. **Performance monitoring** and regression detection
5. **CI/CD integration** patterns for automated testing
6. **Future roadmap** for continued enhancement

### Usage Guidelines

1. **Start with basic templates** for new services
2. **Extend gradually** with advanced patterns as needed
3. **Integrate performance monitoring** from the beginning
4. **Use property-based testing** for comprehensive coverage
5. **Monitor for regressions** in CI/CD pipelines

### Contributing New Patterns

When contributing new patterns to this collection:

1. Follow the established naming conventions
2. Include comprehensive documentation
3. Provide working examples
4. Add type specifications
5. Include performance considerations
6. Document any limitations or caveats

---

**Document Version**: 1.0  
**Last Updated**: 2025-07-02  
**Next Review**: Q1 2025  
**Maintainer**: Foundation Supervision Testing Team