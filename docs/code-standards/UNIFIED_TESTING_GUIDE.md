# Unified Testing Guide

## Core Principles

### The Golden Rules
1. **NEVER use `Process.sleep/1` in tests** - Use event-driven coordination
2. **Every test must be completely independent** - No shared mutable state
3. **Use OTP guarantees instead of timing assumptions** - Trust the platform
4. **Test through public APIs only** - Never access internal state directly
5. **All async operations must have deterministic completion signals** - No guessing

### Philosophy: Event-Driven Deterministic Testing
> "The system should tell us when it's ready, not force us to guess"

Replace arbitrary delays with explicit event coordination. If you find yourself using `Process.sleep/1`, you don't understand what you're waiting for.

## Test Architecture

### Test Categories

#### 1. Destructive Tests (Require Isolation)
Tests that modify state, kill processes, or alter supervisor behavior.

**Setup Pattern:**
```elixir
use Foundation.UnifiedTestFoundation, :supervision_testing
import Foundation.SupervisionTestHelpers

@moduletag :supervision_testing
@moduletag timeout: 30_000

describe "destructive operations" do
  test "service restarts after crash", %{supervision_tree: sup_tree} do
    {:ok, service_pid} = get_service(sup_tree, :my_service)
    
    Process.exit(service_pid, :kill)
    
    {:ok, new_pid} = wait_for_service_restart(sup_tree, :my_service, service_pid)
    assert new_pid != service_pid
    assert Process.alive?(new_pid)
  end
end
```

#### 2. Read-Only Tests (Shared Resources Safe)
Tests that only inspect state without modifications.

**Setup Pattern:**
```elixir
use Foundation.UnifiedTestFoundation, :registry

describe "read-only operations" do
  test "state inspection", %{registry: registry, test_context: ctx} do
    # Safe to use shared resources
  end
end
```

#### 3. Concurrent Operations
Tests involving multiple processes or async operations.

**Setup Pattern:**
```elixir
test "concurrent operations maintain integrity" do
  tasks = for i <- 1..10 do
    Task.async(fn ->
      for j <- 1..50 do
        GenServer.cast(pid, {:increment, i, j})
      end
    end)
  end
  
  # Wait for all tasks
  Enum.each(tasks, &Task.await/1)
  
  # Synchronize with GenServer
  final_count = GenServer.call(pid, :get_count)
  assert final_count == 500
end
```

## Synchronization Patterns

### 1. GenServer Message Ordering (Most Common)
GenServer guarantees FIFO message processing - use this for synchronization.

```elixir
test "async operations complete in order" do
  GenServer.cast(pid, :message_1)     # Async
  GenServer.cast(pid, :message_2)     # Async  
  GenServer.cast(pid, :message_3)     # Async
  
  # Synchronous call ensures all casts processed first
  result = GenServer.call(pid, :get_state)
  assert result.count == 3
end
```

### 2. Process Monitoring
For process lifecycle events.

```elixir
test "process termination detection" do
  ref = Process.monitor(pid)
  Process.exit(pid, :kill)
  
  receive do
    {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
  after
    1000 -> flunk("Process did not terminate")
  end
  
  refute Process.alive?(pid)
end
```

### 3. Event-Driven Coordination
For complex async operations.

```elixir
test "async operation completion" do
  # Wait for specific telemetry event
  assert_telemetry_event [:system, :operation, :completed], 
    %{result: :success} do
    trigger_async_operation()
  end
  
  # Operation guaranteed complete
  verify_final_state()
end
```

### 4. Supervisor Restart Synchronization
For supervision testing.

```elixir
test "supervisor restart behavior" do
  original_pid = Process.whereis(:worker)
  ref = Process.monitor(original_pid)
  
  Process.exit(original_pid, :kill)
  
  # Wait for crash
  receive do
    {:DOWN, ^ref, :process, ^original_pid, _reason} -> :ok
  after
    1000 -> flunk("Process did not terminate")
  end
  
  # Use helper for restart synchronization
  :ok = wait_for_process_restart(:worker, original_pid)
  
  new_pid = Process.whereis(:worker)
  assert new_pid != original_pid
  assert Process.alive?(new_pid)
end
```

## Test Isolation Modes

### Basic Isolation
```elixir
use Foundation.UnifiedTestFoundation, :basic
# Minimal isolation for simple tests
```

### Registry Isolation
```elixir
use Foundation.UnifiedTestFoundation, :registry
# Isolated registry for agent/process tests
```

### Signal Routing Isolation
```elixir
use Foundation.UnifiedTestFoundation, :signal_routing
# Isolated signal bus for event tests
```

### Full Isolation
```elixir
use Foundation.UnifiedTestFoundation, :full_isolation
# Complete service isolation
```

### Contamination Detection
```elixir
use Foundation.UnifiedTestFoundation, :contamination_detection
# Full isolation + contamination monitoring
```

### Supervision Testing
```elixir
use Foundation.UnifiedTestFoundation, :supervision_testing
# Isolated supervision trees for crash recovery tests
```

## Essential Helper Functions

### Process Management
```elixir
# Wait for service restart
{:ok, new_pid} = wait_for_service_restart(sup_tree, :service_name, old_pid, timeout \\ 5000)

# Wait for multiple services
{:ok, new_pids} = wait_for_services_restart(sup_tree, %{service1: pid1, service2: pid2})

# Get service from supervision tree
{:ok, pid} = get_service(sup_tree, :service_name)

# Call service function
result = call_service(sup_tree, :service_name, :function_name)
result = call_service(sup_tree, :service_name, {:function_with_args, [arg1, arg2]})
```

### Generic Waiting
```elixir
# Wait for condition with timeout
result = wait_for(fn ->
  case some_condition() do
    true -> {:ok, :ready}
    false -> nil
  end
end, 5000)
```

### Event Coordination
```elixir
# Wait for telemetry event
assert_telemetry_event [:app, :event, :name], %{key: value} do
  trigger_operation()
end

# Capture multiple events
events = capture_telemetry [:app, :event] do
  perform_operations()
end
```

## Naming Conventions

### Unique Process Names
Always use unique process names to prevent conflicts.

```elixir
# Generate unique names
unique_id = :erlang.unique_integer([:positive])
process_name = :"test_worker_#{unique_id}"

# For multiple related processes in same test
unique_id = :erlang.unique_integer([:positive])
worker_a = :"worker_a_#{unique_id}"
worker_b = :"worker_b_#{unique_id}"
supervisor = :"supervisor_#{unique_id}"
```

### Helper Function Pattern
```elixir
defp create_test_processes(count) do
  unique_id = :erlang.unique_integer([:positive])
  for i <- 1..count do
    process_name = :"test_process_#{i}_#{unique_id}"
    {:ok, pid} = MyProcess.start_link(name: process_name)
    {process_name, pid}
  end
end
```

## Resource Management

### Setup and Cleanup Pattern
```elixir
setup do
  unique_id = :erlang.unique_integer([:positive])
  process_name = :"test_process_#{unique_id}"
  {:ok, pid} = MyProcess.start_link(name: process_name)
  
  on_exit(fn ->
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after 100 -> :ok
      end
    end
  end)
  
  {:ok, pid: pid, name: process_name}
end
```

### Error Suppression
Only suppress expected errors during intentional crash tests.

```elixir
test "intentional crash scenarios" do
  # Suppress only expected errors
  capture_log(fn ->
    Process.exit(pid, :kill)
  end)
  
  # Verify recovery
  assert Process.alive?(new_pid)
end
```

## Common Anti-Patterns and Solutions

### ❌ Sleep-Based Testing
```elixir
# WRONG - Timing-dependent and flaky
test "async operation" do
  GenServer.cast(pid, :do_something)
  Process.sleep(100)  # Flaky and unreliable
  assert some_condition()
end
```

### ✅ Event-Driven Testing
```elixir
# CORRECT - Deterministic and reliable
test "async operation" do
  assert_telemetry_event [:app, :operation, :completed], %{} do
    GenServer.cast(pid, :do_something)
  end
  assert some_condition()
end
```

### ❌ Internal State Access
```elixir
# WRONG - Brittle and implementation-dependent
test "internal state" do
  state = :sys.get_state(pid)
  assert state.counter == 5
end
```

### ✅ Public API Testing
```elixir
# CORRECT - Stable and behavior-focused
test "counter behavior" do
  result = MyProcess.get_counter(pid)
  assert result == 5
end
```

### ❌ Hardcoded Global Names
```elixir
# WRONG - Causes test conflicts
test "process functionality" do
  {:ok, _} = MyProcess.start_link(name: :hardcoded_name)
  # Risk of conflicts with other tests
end
```

### ✅ Unique Process Naming
```elixir
# CORRECT - No conflicts possible
test "process functionality" do
  unique_id = :erlang.unique_integer([:positive])
  name = :"test_process_#{unique_id}"
  {:ok, _} = MyProcess.start_link(name: name)
end
```

## Advanced Testing Patterns

### Property-Based Testing
```elixir
use ExUnitProperties
import StreamData

property "operation handles any valid input" do
  check all input <- valid_input_generator() do
    result = MyModule.process(input)
    assert is_valid_result(result)
  end
end
```

### Chaos Testing
```elixir
test "system survives random failures" do
  chaos_task = Task.async(fn ->
    run_chaos_loop(sup_tree, 30_000)  # 30 seconds
  end)
  
  health_task = Task.async(fn ->
    monitor_system_health(sup_tree, 30_000)
  end)
  
  chaos_events = Task.await(chaos_task, 35_000)
  health_results = Task.await(health_task, 35_000)
  
  assert length(chaos_events) > 0
  assert Enum.all?(health_results, & &1.healthy)
end
```

### Performance Testing
```elixir
test "restart time benchmarks" do
  times = for _i <- 1..10 do
    {:ok, pid} = get_service(sup_tree, :service)
    
    start_time = :erlang.monotonic_time(:microsecond)
    Process.exit(pid, :kill)
    {:ok, _new_pid} = wait_for_service_restart(sup_tree, :service, pid)
    end_time = :erlang.monotonic_time(:microsecond)
    
    (end_time - start_time) / 1000  # Convert to milliseconds
  end
  
  avg_time = Enum.sum(times) / length(times)
  p95_time = percentile(times, 0.95)
  
  assert avg_time < 1000, "Average restart too slow: #{avg_time}ms"
  assert p95_time < 3000, "P95 restart too slow: #{p95_time}ms"
end
```

## Testing Supervision Strategies

### One-for-One Strategy
```elixir
test "one_for_one only restarts crashed child" do
  children = get_all_children(supervisor)
  target_child = Enum.find(children, &(&1.id == :target))
  
  # Monitor all children
  monitors = for child <- children do
    {child.id, Process.monitor(child.pid)}
  end
  
  # Kill target child
  Process.exit(target_child.pid, :kill)
  
  # Only target child should restart
  receive do
    {:DOWN, ref, :process, pid, _} when pid == target_child.pid -> :ok
  after 1000 -> flunk("Target child did not crash")
  end
  
  # Wait for restart
  :ok = wait_for_child_restart(supervisor, :target, target_child.pid)
  
  # Other children should be unchanged
  for {child_id, ref} <- monitors, child_id != :target do
    refute_received {:DOWN, ^ref, :process, _, _}
  end
end
```

### Rest-for-One Strategy
```elixir
test "rest_for_one restarts subsequent children" do
  monitors = monitor_all_services(sup_tree)
  
  # Kill service in middle of supervision order
  {target_pid, _} = monitors[:middle_service]
  Process.exit(target_pid, :kill)
  
  # Verify cascade behavior
  verify_rest_for_one_cascade(monitors, :middle_service)
  
  # Services before target should remain alive
  {early_pid, _} = monitors[:early_service]
  {:ok, current_early_pid} = get_service(sup_tree, :early_service)
  assert early_pid == current_early_pid
end
```

## Test Organization

### File Structure
```
test/
├── test_helper.exs
├── support/
│   ├── supervision_test_helpers.ex
│   ├── unified_test_foundation.ex
│   └── async_test_helpers.ex
├── [app_name]/
│   ├── core/
│   ├── services/
│   └── supervision/
└── [app_name]_web/
    ├── controllers/
    └── live/
```

### Test Grouping
Group tests by isolation requirements, not just by module.

```elixir
defmodule MyModuleTest do
  use ExUnit.Case, async: true
  
  describe "destructive operations" do
    setup do
      SupervisorTestHelper.setup_isolated_supervisor("destructive")
    end
    # Tests that modify state
  end
  
  describe "read-only operations" do
    setup do
      SupervisorTestHelper.get_demo_supervisor()
    end
    # Tests that only read state
  end
  
  describe "error scenarios" do
    setup do
      SupervisorTestHelper.setup_crash_test_supervisor("errors")
    end
    # Tests for error conditions
  end
end
```

## Quality Assurance

### Automated Validation
```bash
# CI checks
rg "Process\.sleep\(" test/ --type elixir && exit 1
rg "name: :[a-z_]+\b" test/ --type elixir | grep -v "unique_integer" && exit 1

# Race condition detection
for i in {1..3}; do
  mix test --seed $RANDOM || exit 1
done
```

### Code Review Checklist
- [ ] No `Process.sleep/1` usage
- [ ] Unique process naming
- [ ] Proper isolation mode selection
- [ ] Event-driven synchronization
- [ ] Resource cleanup implementation
- [ ] Public API testing only

## Migration Strategy

### From Legacy Tests
1. **Identify test category** (destructive/read-only/error)
2. **Select appropriate isolation mode**
3. **Replace `Process.sleep/1` with proper synchronization**
4. **Implement unique naming**
5. **Add proper cleanup**
6. **Validate independence**

### Example Migration
```elixir
# BEFORE - Legacy test
test "old test" do
  {:ok, pid} = MyWorker.start_link(name: :test_worker)
  Process.exit(pid, :kill)
  Process.sleep(100)  # Hope it restarted
  new_pid = Process.whereis(:test_worker)
  assert new_pid != pid
end

# AFTER - Modern test
test "service restart", %{supervision_tree: sup_tree} do
  {:ok, pid} = get_service(sup_tree, :my_worker)
  Process.exit(pid, :kill)
  {:ok, new_pid} = wait_for_service_restart(sup_tree, :my_worker, pid)
  assert new_pid != pid
end
```

## Summary

### Key Takeaways
1. **Event-driven coordination** replaces timing guesswork
2. **Test isolation** prevents contamination and enables parallelism
3. **OTP guarantees** provide reliable synchronization mechanisms
4. **Helper functions** encapsulate common patterns
5. **Unique naming** eliminates resource conflicts
6. **Proper cleanup** ensures test independence

### Success Metrics
- Zero `Process.sleep/1` usage in tests
- <0.1% flaky test failure rate
- Tests pass reliably under load
- Parallel execution without conflicts
- Fast feedback loops (complete as soon as conditions met)

This guide represents the synthesis of extensive testing experience and provides battle-tested patterns for building robust, maintainable test suites that scale with your application.