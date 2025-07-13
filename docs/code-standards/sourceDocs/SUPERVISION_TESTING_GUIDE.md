# Supervision Testing Guide

**Document Version**: 1.0  
**Date**: 2025-07-02  
**Purpose**: Comprehensive guide for implementing supervision crash recovery tests with isolated supervision trees

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture Overview](#architecture-overview) 
3. [Test Foundation Setup](#test-foundation-setup)
4. [Writing Supervision Tests](#writing-supervision-tests)
5. [Helper Functions Reference](#helper-functions-reference)
6. [Best Practices](#best-practices)
7. [Common Patterns](#common-patterns)
8. [Troubleshooting](#troubleshooting)
9. [Migration Guide](#migration-guide)
10. [Advanced Usage](#advanced-usage)

---

## Quick Start

### 1. Basic Supervision Test Template

```elixir
defmodule MyApp.SupervisionTest do
  @moduledoc """
  Example supervision crash recovery test using isolated supervision trees.
  """
  
  # Use the supervision testing mode from UnifiedTestFoundation
  use Foundation.UnifiedTestFoundation, :supervision_testing
  
  # Import supervision testing helpers
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag timeout: 30_000
  
  describe "Service crash recovery" do
    test "service restarts after crash", %{supervision_tree: sup_tree} do
      # Get service from isolated supervision tree
      {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
      assert is_pid(service_pid)
      
      # Test functionality before crash
      stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
      assert is_map(stats)
      
      # Kill the service
      Process.exit(service_pid, :kill)
      
      # Wait for restart
      {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, service_pid)
      
      # Verify restart and functionality
      assert new_pid != service_pid
      assert Process.alive?(new_pid)
      
      # Test functionality after restart
      new_stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
      assert is_map(new_stats)
    end
  end
end
```

### 2. Running Your Tests

```bash
# Run individual test
mix test test/my_app/supervision_test.exs:25

# Run all supervision tests
mix test test/my_app/supervision_test.exs

# Run with detailed output
mix test test/my_app/supervision_test.exs --trace

# Run multiple times to verify consistency
for i in {1..5}; do mix test test/my_app/supervision_test.exs; done
```

---

## Architecture Overview

### Isolated Supervision Trees

Each test gets its own complete supervision tree with isolated services:

```
Test Execution Environment
├── Global JidoFoundation (Production)
│   ├── JidoFoundation.TaskPoolManager (PID: <0.123.0>)
│   ├── JidoFoundation.SystemCommandManager (PID: <0.124.0>)
│   └── ...
│
├── Test 1 Isolated Supervision
│   ├── Test Registry: test_jido_registry_1001
│   ├── Test Supervisor: test_jido_supervisor_1001
│   ├── TaskPoolManager (PID: <0.201.0>) ← Isolated instance
│   ├── SystemCommandManager (PID: <0.202.0>) ← Isolated instance
│   └── ...
│
└── Test 2 Isolated Supervision
    ├── Test Registry: test_jido_registry_1002
    ├── Test Supervisor: test_jido_supervisor_1002  
    ├── TaskPoolManager (PID: <0.301.0>) ← Different isolated instance
    └── ...
```

### Key Components

1. **Foundation.UnifiedTestFoundation** - Main test foundation with `:supervision_testing` mode
2. **Foundation.SupervisionTestHelpers** - Helper functions for service access and monitoring
3. **Foundation.SupervisionTestSetup** - Infrastructure for creating isolated supervision trees
4. **Foundation.IsolatedServiceDiscovery** - Service discovery utilities for test context

---

## Test Foundation Setup

### 1. Enable Supervision Testing Mode

```elixir
defmodule MyApp.SupervisionTest do
  # This enables isolated supervision testing
  use Foundation.UnifiedTestFoundation, :supervision_testing
  
  # This provides supervision-specific helper functions
  import Foundation.SupervisionTestHelpers
  
  # Mark tests for proper categorization
  @moduletag :supervision_testing
  @moduletag timeout: 30_000  # Supervision tests may take longer
end
```

### 2. Understanding Test Context

When you use `:supervision_testing` mode, your tests receive a `supervision_tree` context:

```elixir
test "example", %{supervision_tree: sup_tree} do
  # sup_tree contains:
  # - test_id: Unique identifier for this test
  # - registry: Test-specific registry name  
  # - registry_pid: Registry process PID
  # - supervisor: Test-specific supervisor name
  # - supervisor_pid: Supervisor process PID
  # - services: List of available services
  
  IO.inspect(sup_tree)
  # %{
  #   test_id: 1001,
  #   registry: :test_jido_registry_1001,
  #   registry_pid: #PID<0.200.0>,
  #   supervisor: :test_jido_supervisor_1001,
  #   supervisor_pid: #PID<0.201.0>,
  #   services: [JidoFoundation.TaskPoolManager, ...]
  # }
end
```

### 3. Automatic Setup and Cleanup

The supervision testing foundation automatically:

```elixir
# Before each test:
# 1. Creates unique test registry
# 2. Starts isolated supervision tree
# 3. Waits for all services to be ready
# 4. Validates supervision context

# After each test:
# 5. Gracefully shuts down supervision tree
# 6. Cleans up test registry
# 7. Verifies no process leaks
# 8. Logs cleanup completion
```

---

## Writing Supervision Tests

### 1. Service Access Patterns

#### Get Service Instance
```elixir
test "service access", %{supervision_tree: sup_tree} do
  # Get service PID from isolated supervision tree
  {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
  assert is_pid(task_pid)
  assert Process.alive?(task_pid)
  
  # Error handling
  case get_service(sup_tree, :unknown_service) do
    {:error, {:unknown_service, :unknown_service}} -> :expected
    other -> flunk("Unexpected result: #{inspect(other)}")
  end
end
```

#### Make Service Calls
```elixir
test "service interaction", %{supervision_tree: sup_tree} do
  # Simple function call
  stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
  assert is_map(stats)
  
  # Function call with arguments
  result = call_service(sup_tree, :task_pool_manager, {:create_pool, [
    :test_pool, 
    %{max_concurrency: 4, timeout: 5000}
  ]})
  assert result == :ok
  
  # Call with custom timeout
  result = call_service(sup_tree, :system_command_manager, :get_load_average, 10_000)
  assert {:ok, _load} = result
end
```

### 2. Crash Recovery Testing

#### Basic Crash and Restart
```elixir
test "basic crash recovery", %{supervision_tree: sup_tree} do
  # Get initial service
  {:ok, initial_pid} = get_service(sup_tree, :task_pool_manager)
  
  # Monitor for crash detection
  ref = Process.monitor(initial_pid)
  
  # Kill the service
  Process.exit(initial_pid, :kill)
  
  # Wait for DOWN message
  assert_receive {:DOWN, ^ref, :process, ^initial_pid, :killed}, 2000
  
  # Wait for supervisor to restart it
  {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, initial_pid)
  
  # Verify restart
  assert new_pid != initial_pid
  assert Process.alive?(new_pid)
end
```

#### Testing Multiple Service Crashes
```elixir
test "multiple service crashes", %{supervision_tree: sup_tree} do
  # Get services
  {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
  {:ok, sys_pid} = get_service(sup_tree, :system_command_manager)
  
  # Monitor both
  task_ref = Process.monitor(task_pid)
  sys_ref = Process.monitor(sys_pid)
  
  # Kill both simultaneously
  Process.exit(task_pid, :kill)
  Process.exit(sys_pid, :kill)
  
  # Wait for both to go down
  assert_receive {:DOWN, ^task_ref, :process, ^task_pid, :killed}, 2000
  assert_receive {:DOWN, ^sys_ref, :process, ^sys_pid, :killed}, 2000
  
  # Wait for both to restart
  {:ok, new_task_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, task_pid, 8000)
  {:ok, new_sys_pid} = wait_for_service_restart(sup_tree, :system_command_manager, sys_pid, 8000)
  
  # Verify both restarted
  assert new_task_pid != task_pid
  assert new_sys_pid != sys_pid
end
```

### 3. Supervision Strategy Testing

#### Rest-for-One Verification
```elixir
test "rest_for_one supervision strategy", %{supervision_tree: sup_tree} do
  # Monitor all services
  monitors = monitor_all_services(sup_tree)
  
  # Kill TaskPoolManager (position 2 in supervision order)
  {task_pid, _} = monitors[:task_pool_manager]
  Process.exit(task_pid, :kill)
  
  # Verify rest_for_one cascade behavior
  verify_rest_for_one_cascade(monitors, :task_pool_manager)
  
  # Expected behavior:
  # - SchedulerManager (position 1): Stays alive
  # - TaskPoolManager (position 2): Restarts  
  # - SystemCommandManager (position 3): Restarts
  # - CoordinationManager (position 4): Restarts
  
  # Verify SchedulerManager is still alive (not restarted)
  {sched_pid, _} = monitors[:scheduler_manager]
  {:ok, current_sched_pid} = get_service(sup_tree, :scheduler_manager)
  assert sched_pid == current_sched_pid
end
```

### 4. Resource Monitoring

#### Process Leak Detection
```elixir
test "no process leaks after crashes", %{supervision_tree: sup_tree} do
  initial_count = :erlang.system_info(:process_count)
  
  # Crash and restart service multiple times
  for _i <- 1..5 do
    {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
    Process.exit(service_pid, :kill)
    {:ok, _new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, service_pid)
  end
  
  # Allow system to stabilize
  Process.sleep(1000)
  
  final_count = :erlang.system_info(:process_count)
  
  # Verify no significant process growth
  assert final_count - initial_count < 20,
         "Process count grew significantly: #{initial_count} -> #{final_count}"
end
```

#### ETS Table Management
```elixir
test "ETS tables are cleaned up", %{supervision_tree: sup_tree} do
  initial_ets_count = :erlang.system_info(:ets_count)
  
  # Create services that might use ETS tables
  {:ok, sys_pid} = get_service(sup_tree, :system_command_manager)
  
  # Crash service multiple times
  for _i <- 1..3 do
    Process.exit(sys_pid, :kill)
    {:ok, sys_pid} = wait_for_service_restart(sup_tree, :system_command_manager, sys_pid)
  end
  
  final_ets_count = :erlang.system_info(:ets_count)
  
  # ETS count should not grow significantly
  assert final_ets_count - initial_ets_count < 10,
         "ETS count grew unexpectedly: #{initial_ets_count} -> #{final_ets_count}"
end
```

### 5. Functionality Testing

#### State Recovery Verification
```elixir
test "service maintains configuration after restart", %{supervision_tree: sup_tree} do
  # Set up initial configuration
  assert :ok = call_service(sup_tree, :task_pool_manager, {:create_pool, [
    :test_pool, 
    %{max_concurrency: 7, timeout: 3000}
  ]})
  
  {:ok, initial_stats} = call_service(sup_tree, :task_pool_manager, {:get_pool_stats, [:test_pool]})
  assert initial_stats.max_concurrency == 7
  
  # Crash the service
  {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
  Process.exit(service_pid, :kill)
  
  # Wait for restart
  {:ok, _new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, service_pid)
  
  # Verify default pools are recreated (custom pools may be lost)
  case call_service(sup_tree, :task_pool_manager, {:get_pool_stats, [:general]}) do
    {:ok, general_stats} -> assert is_map(general_stats)
    {:error, _} -> :ok  # Pool may not be ready yet
  end
end
```

---

## Helper Functions Reference

### Service Access Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `get_service/2` | Get service PID | `{:ok, pid} = get_service(sup_tree, :task_pool_manager)` |
| `call_service/3` | Call service function | `stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)` |
| `call_service/4` | Call with timeout | `result = call_service(sup_tree, :service, :func, 10_000)` |
| `cast_service/3` | Cast to service | `cast_service(sup_tree, :service, {:update, config})` |

### Process Monitoring Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `monitor_all_services/1` | Monitor all services | `monitors = monitor_all_services(sup_tree)` |
| `wait_for_service_restart/3` | Wait for restart | `{:ok, new_pid} = wait_for_service_restart(sup_tree, :service, old_pid)` |
| `wait_for_service_restart/4` | Wait with timeout | `wait_for_service_restart(sup_tree, :service, old_pid, 8000)` |
| `wait_for_services_restart/2` | Wait for multiple | `{:ok, new_pids} = wait_for_services_restart(sup_tree, old_pids)` |

### Supervision Testing Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `verify_rest_for_one_cascade/2` | Test cascade behavior | `verify_rest_for_one_cascade(monitors, :task_pool_manager)` |
| `wait_for_services_ready/1` | Wait for startup | `wait_for_services_ready(sup_tree)` |
| `validate_supervision_context/1` | Validate context | `assert validate_supervision_context(sup_tree) == :ok` |

### Utility Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `get_supervision_order/0` | Get start order | `order = get_supervision_order()` |
| `get_supported_services/0` | Get service list | `services = get_supported_services()` |
| `service_name_to_module/1` | Convert name to module | `module = service_name_to_module(:task_pool_manager)` |

---

## Best Practices

### 1. Test Structure

#### ✅ Good Test Structure
```elixir
describe "Service crash recovery" do
  test "service restarts and maintains functionality", %{supervision_tree: sup_tree} do
    # 1. Setup: Get initial state
    {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
    initial_stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
    
    # 2. Action: Perform crash
    Process.exit(service_pid, :kill)
    
    # 3. Verification: Check restart
    {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, service_pid)
    assert new_pid != service_pid
    
    # 4. Functionality: Verify service works
    new_stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
    assert is_map(new_stats)
  end
end
```

#### ❌ Poor Test Structure
```elixir
test "stuff", %{supervision_tree: sup_tree} do
  # Testing too many things at once
  {:ok, pid1} = get_service(sup_tree, :task_pool_manager)
  {:ok, pid2} = get_service(sup_tree, :system_command_manager)
  Process.exit(pid1, :kill)
  Process.exit(pid2, :kill)
  # ... lots of different assertions
  # Hard to debug when it fails
end
```

### 2. Timeout Handling

#### ✅ Appropriate Timeouts
```elixir
test "service restart timing", %{supervision_tree: sup_tree} do
  {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
  Process.exit(service_pid, :kill)
  
  # Use longer timeout for complex services
  {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, service_pid, 8000)
  
  # Use shorter timeout for simple calls
  stats = call_service(sup_tree, :task_pool_manager, :get_all_stats, 2000)
end
```

#### ❌ Poor Timeout Handling
```elixir
test "bad timeouts", %{supervision_tree: sup_tree} do
  # Too short - may cause flaky tests
  {:ok, new_pid} = wait_for_service_restart(sup_tree, :service, old_pid, 100)
  
  # Too long - makes tests slow
  stats = call_service(sup_tree, :service, :simple_call, 30_000)
end
```

### 3. Error Handling

#### ✅ Robust Error Handling
```elixir
test "service error handling", %{supervision_tree: sup_tree} do
  case call_service(sup_tree, :system_command_manager, :get_load_average) do
    {:ok, load_avg} -> 
      assert is_float(load_avg)
    {:error, reason} -> 
      # Expected in some test environments
      assert reason in [:command_not_found, :system_unavailable]
    :ok -> 
      # Test service may return simplified responses
      :ok
  end
end
```

### 4. Resource Management

#### ✅ Proper Resource Tracking
```elixir
test "resource management", %{supervision_tree: sup_tree, initial_process_count: initial_count} do
  # Test implementation...
  
  # Always check for resource leaks
  final_count = :erlang.system_info(:process_count)
  assert final_count - initial_count < 20,
         "Process leak detected: #{initial_count} -> #{final_count}"
end
```

---

## Common Patterns

### 1. Basic Service Restart Pattern

```elixir
def test_service_restart(sup_tree, service_name) do
  # Get service
  {:ok, service_pid} = get_service(sup_tree, service_name)
  
  # Test it's working
  assert Process.alive?(service_pid)
  
  # Kill it
  Process.exit(service_pid, :kill)
  
  # Wait for restart
  {:ok, new_pid} = wait_for_service_restart(sup_tree, service_name, service_pid)
  
  # Verify restart
  assert new_pid != service_pid
  assert Process.alive?(new_pid)
end

# Usage in tests
test "task pool manager restart", %{supervision_tree: sup_tree} do
  test_service_restart(sup_tree, :task_pool_manager)
end
```

### 2. Supervision Strategy Testing Pattern

```elixir
def test_rest_for_one_behavior(sup_tree, crashed_service) do
  # Monitor all services
  monitors = monitor_all_services(sup_tree)
  
  # Get the service to crash
  {crashed_pid, _} = monitors[crashed_service]
  
  # Kill the service
  Process.exit(crashed_pid, :kill)
  
  # Verify cascade behavior
  verify_rest_for_one_cascade(monitors, crashed_service)
  
  # Wait for restarts
  wait_for_affected_services_restart(sup_tree, crashed_service)
end

# Usage in tests
test "task pool manager cascade", %{supervision_tree: sup_tree} do
  test_rest_for_one_behavior(sup_tree, :task_pool_manager)
end
```

### 3. Functionality Testing Pattern

```elixir
def test_service_functionality_after_restart(sup_tree, service_name, functionality_test) do
  # Test before crash
  functionality_test.(sup_tree, :before_crash)
  
  # Crash service
  {:ok, service_pid} = get_service(sup_tree, service_name)
  Process.exit(service_pid, :kill)
  
  # Wait for restart
  {:ok, _new_pid} = wait_for_service_restart(sup_tree, service_name, service_pid)
  
  # Test after restart
  functionality_test.(sup_tree, :after_restart)
end

# Usage in tests
test "task pool functionality after restart", %{supervision_tree: sup_tree} do
  functionality_test = fn sup_tree, _phase ->
    stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
    assert is_map(stats)
  end
  
  test_service_functionality_after_restart(sup_tree, :task_pool_manager, functionality_test)
end
```

### 4. Resource Monitoring Pattern

```elixir
def with_resource_monitoring(test_function) do
  fn context ->
    initial_processes = :erlang.system_info(:process_count)
    initial_ets = :erlang.system_info(:ets_count)
    
    # Run the test
    result = test_function.(context)
    
    # Check for leaks
    final_processes = :erlang.system_info(:process_count)
    final_ets = :erlang.system_info(:ets_count)
    
    assert final_processes - initial_processes < 20,
           "Process leak: #{initial_processes} -> #{final_processes}"
    assert final_ets - initial_ets < 10,
           "ETS leak: #{initial_ets} -> #{final_ets}"
    
    result
  end
end

# Usage in tests
test "monitored service restart", context do
  with_resource_monitoring(fn %{supervision_tree: sup_tree} ->
    test_service_restart(sup_tree, :task_pool_manager)
  end).(context)
end
```

---

## Troubleshooting

### Common Issues and Solutions

#### Issue: Test Timeouts
```
** (ExUnit.AssertionError) 
Expected service to restart within 5000ms
```

**Solution**: Increase timeout for complex services
```elixir
# Instead of default 5000ms
{:ok, new_pid} = wait_for_service_restart(sup_tree, :service, old_pid, 10_000)
```

#### Issue: Service Not Found
```
** (ExUnit.AssertionError) 
{:error, :service_not_found}
```

**Solution**: Ensure service is available and spelled correctly
```elixir
# Check supported services
supported = get_supported_services()
IO.inspect(supported)  # [:task_pool_manager, :system_command_manager, ...]

# Validate supervision context
assert validate_supervision_context(sup_tree) == :ok
```

#### Issue: Process Already Dead
```
** (ExUnit.AssertionError) 
{:error, :service_not_alive}
```

**Solution**: Check service state before operations
```elixir
case get_service(sup_tree, :service_name) do
  {:ok, pid} when is_pid(pid) ->
    assert Process.alive?(pid)
    # Continue with test
  {:error, reason} ->
    flunk("Service not available: #{inspect(reason)}")
end
```

#### Issue: Flaky Tests
```
Test passes sometimes, fails other times
```

**Solution**: Add proper synchronization
```elixir
# Wait for services to be ready
wait_for_services_ready(sup_tree, [:task_pool_manager, :system_command_manager])

# Use proper timeouts
{:ok, new_pid} = wait_for_service_restart(sup_tree, :service, old_pid, 8000)

# Wait for dependent operations
wait_for_services_restart(sup_tree, %{service1: pid1, service2: pid2})
```

### Debugging Techniques

#### 1. Add Detailed Logging
```elixir
test "debug test", %{supervision_tree: sup_tree} do
  require Logger
  
  Logger.info("Starting test with supervision context: #{inspect(sup_tree)}")
  
  {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
  Logger.info("Got service PID: #{inspect(service_pid)}")
  
  Process.exit(service_pid, :kill)
  Logger.info("Killed service, waiting for restart...")
  
  {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, service_pid)
  Logger.info("Service restarted with new PID: #{inspect(new_pid)}")
end
```

#### 2. Inspect Process Tree
```elixir
test "inspect supervision tree", %{supervision_tree: sup_tree} do
  # Get supervisor info
  children = Supervisor.which_children(sup_tree.supervisor_pid)
  IO.inspect(children, label: "Supervisor children")
  
  # Get registry contents
  services = Registry.select(sup_tree.registry, [{{:"$1", :"$2", :"$3"}, [], [:"$_"]}])
  IO.inspect(services, label: "Registry contents")
end
```

#### 3. Monitor Process Messages
```elixir
test "monitor messages", %{supervision_tree: sup_tree} do
  {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
  
  # Monitor the process
  ref = Process.monitor(service_pid)
  
  Process.exit(service_pid, :kill)
  
  # Wait and inspect the DOWN message
  receive do
    {:DOWN, ^ref, :process, ^service_pid, reason} ->
      IO.inspect(reason, label: "Process terminated with reason")
  after
    5000 ->
      IO.inspect("No DOWN message received")
  end
end
```

---

## Migration Guide

### Migrating from Global to Isolated Tests

#### Step 1: Update Test Module Declaration

**Before:**
```elixir
defmodule MyApp.SupervisionTest do
  use ExUnit.Case, async: false
  
  alias JidoFoundation.TaskPoolManager
end
```

**After:**
```elixir
defmodule MyApp.SupervisionTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  
  import Foundation.SupervisionTestHelpers
  
  @moduletag :supervision_testing
  @moduletag timeout: 30_000
end
```

#### Step 2: Convert Service Access

**Before:**
```elixir
test "old way" do
  # Using global service
  pid = Process.whereis(JidoFoundation.TaskPoolManager)
  stats = JidoFoundation.TaskPoolManager.get_all_stats()
end
```

**After:**
```elixir
test "new way", %{supervision_tree: sup_tree} do
  # Using isolated service
  {:ok, pid} = get_service(sup_tree, :task_pool_manager)
  stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
end
```

#### Step 3: Update Process Monitoring

**Before:**
```elixir
test "old monitoring" do
  pid = Process.whereis(JidoFoundation.TaskPoolManager)
  ref = Process.monitor(pid)
  Process.exit(pid, :kill)
  
  assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
  
  # Manual waiting for restart
  :timer.sleep(2000)
  new_pid = Process.whereis(JidoFoundation.TaskPoolManager)
  assert new_pid != pid
end
```

**After:**
```elixir
test "new monitoring", %{supervision_tree: sup_tree} do
  {:ok, pid} = get_service(sup_tree, :task_pool_manager)
  Process.exit(pid, :kill)
  
  # Helper function handles monitoring and waiting
  {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, pid)
  assert new_pid != pid
end
```

#### Step 4: Convert Setup/Teardown

**Before:**
```elixir
setup do
  # Custom setup for global state
  initial_count = :erlang.system_info(:process_count)
  
  on_exit(fn ->
    # Custom cleanup
    final_count = :erlang.system_info(:process_count)
    if final_count > initial_count + 20 do
      Logger.warning("Potential process leak")
    end
  end)
  
  %{initial_count: initial_count}
end
```

**After:**
```elixir
# Setup is automatic with :supervision_testing mode
# No manual setup/teardown needed
# Resource monitoring is built-in
```

### Migration Checklist

- [ ] Update module declaration to use `Foundation.UnifiedTestFoundation, :supervision_testing`
- [ ] Import `Foundation.SupervisionTestHelpers`
- [ ] Add `@moduletag :supervision_testing`
- [ ] Update test function signatures to accept `%{supervision_tree: sup_tree}`
- [ ] Replace `Process.whereis/1` with `get_service/2`
- [ ] Replace direct module calls with `call_service/3`
- [ ] Replace manual restart waiting with `wait_for_service_restart/3`
- [ ] Remove manual process monitoring in favor of helper functions
- [ ] Remove custom setup/teardown in favor of automatic management
- [ ] Test in isolation and batch to verify no contamination

---

## Advanced Usage

### 1. Custom Service Testing

```elixir
defmodule MyApp.CustomServiceTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  import Foundation.SupervisionTestHelpers
  
  # Define custom service mappings if needed
  @custom_services %{
    my_custom_service: MyApp.CustomService
  }
  
  def get_custom_service(sup_tree, service_name) do
    service_module = Map.get(@custom_services, service_name)
    
    case Registry.lookup(sup_tree.registry, {:service, service_module}) do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      [] -> {:error, :service_not_found}
    end
  end
  
  test "custom service crash recovery", %{supervision_tree: sup_tree} do
    {:ok, service_pid} = get_custom_service(sup_tree, :my_custom_service)
    # Test custom service...
  end
end
```

### 2. Complex Supervision Scenarios

```elixir
test "complex failure scenario", %{supervision_tree: sup_tree} do
  # Setup: Create complex state
  for i <- 1..5 do
    assert :ok = call_service(sup_tree, :task_pool_manager, {:create_pool, [
      :"test_pool_#{i}",
      %{max_concurrency: i, timeout: 5000}
    ]})
  end
  
  # Action: Multiple cascading failures
  monitors = monitor_all_services(sup_tree)
  
  # Kill services in dependency order
  {task_pid, _} = monitors[:task_pool_manager]
  {sys_pid, _} = monitors[:system_command_manager]
  
  Process.exit(task_pid, :kill)
  Process.exit(sys_pid, :kill)
  
  # Verification: System recovers completely
  {:ok, _} = wait_for_services_restart(sup_tree, %{
    task_pool_manager: task_pid,
    system_command_manager: sys_pid
  })
  
  # Verify complex state is recovered appropriately
  # (pools may be recreated with defaults)
  stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
  assert is_map(stats)
end
```

### 3. Performance Testing

```elixir
test "supervision performance under load", %{supervision_tree: sup_tree} do
  # Measure restart time under various conditions
  restart_times = for _i <- 1..10 do
    {:ok, service_pid} = get_service(sup_tree, :task_pool_manager)
    
    start_time = :erlang.monotonic_time(:millisecond)
    Process.exit(service_pid, :kill)
    
    {:ok, _new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, service_pid)
    end_time = :erlang.monotonic_time(:millisecond)
    
    end_time - start_time
  end
  
  avg_restart_time = Enum.sum(restart_times) / length(restart_times)
  max_restart_time = Enum.max(restart_times)
  
  # Assert performance requirements
  assert avg_restart_time < 1000, "Average restart time too slow: #{avg_restart_time}ms"
  assert max_restart_time < 2000, "Max restart time too slow: #{max_restart_time}ms"
end
```

### 4. Integration with Property-Based Testing

```elixir
defmodule MyApp.PropertyBasedSupervisionTest do
  use Foundation.UnifiedTestFoundation, :supervision_testing
  use ExUnitProperties
  
  import Foundation.SupervisionTestHelpers
  
  property "services always restart after crashes", %{supervision_tree: sup_tree} do
    check all service_name <- member_of(get_supported_services()),
              kill_signal <- member_of([:kill, :shutdown, :normal]),
              max_runs: 50 do
      
      {:ok, original_pid} = get_service(sup_tree, service_name)
      Process.exit(original_pid, kill_signal)
      
      {:ok, new_pid} = wait_for_service_restart(sup_tree, service_name, original_pid, 10_000)
      
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end
  end
end
```

---

## Conclusion

This guide provides comprehensive patterns and practices for implementing robust supervision crash recovery tests using isolated supervision trees. The key benefits of this approach are:

1. **Test Reliability**: Complete elimination of test contamination
2. **OTP Compliance**: Proper supervision testing patterns  
3. **Resource Safety**: Automatic cleanup and leak detection
4. **Maintainability**: Reusable helpers and clear patterns
5. **Performance**: Faster and more consistent test execution

For questions or improvements to this guide, refer to the implementation in:
- `test/support/supervision_test_helpers.ex`
- `test/support/supervision_test_setup.ex`
- `test/jido_foundation/supervision_crash_recovery_test.exs`

---

**Guide Version**: 1.0  
**Last Updated**: 2025-07-02  
**Tested With**: Elixir 1.15+, OTP 26+  
**Status**: Production Ready