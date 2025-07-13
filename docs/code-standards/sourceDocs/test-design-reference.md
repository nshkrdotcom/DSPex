# OTP Test Design and Build Reference

## Overview

This document serves as the master reference for designing and building robust, maintainable tests in the OTP Supervisor Educational Tool project. It synthesizes lessons learned from extensive test refactoring, compliance audits, and architectural improvements to provide comprehensive guidance for test development.

## Core Philosophy

### Test Independence Principle
Every test must be **completely independent** and should not affect or be affected by other tests. This principle drives all architectural decisions and patterns in our test suite.

### Educational Value Preservation
Tests serve dual purposes: validation and education. All testing patterns must preserve and enhance the educational value of the codebase while ensuring robust test execution.

### OTP Compliance First
All test patterns must align with OTP principles and leverage OTP guarantees rather than working around them.

## Test Architecture Overview

### Test Categories

#### 1. Destructive Tests (Isolation Required)
Tests that modify state, kill processes, or alter supervisor behavior **MUST** use isolated supervisors.

**Characteristics:**
- Process killing/restarting
- State mutations
- Supervisor crash testing
- Error injection scenarios

**Setup Pattern:**
```elixir
describe "destructive operations" do
  setup do
    SupervisorTestHelper.setup_isolated_supervisor("test_category")
  end
  
  test "safe process manipulation", %{supervisor: supervisor} do
    # Isolated - no conflicts with other tests
  end
end
```

#### 2. Read-Only Tests (Shared Resources Safe)
Tests that only read state without modifications can use shared demo supervisors.

**Characteristics:**
- State inspection
- Process information display
- Supervisor tree traversal
- UI rendering without modification

**Setup Pattern:**
```elixir
describe "read-only operations" do
  setup do
    SupervisorTestHelper.get_demo_supervisor()
  end
  
  test "safe state inspection", %{supervisor: supervisor} do
    # Shared supervisor - no mutations
  end
end
```

#### 3. Error Handling Tests (Special Isolation)
Tests for error scenarios should use temporary supervisors designed to fail.

**Setup Pattern:**
```elixir
describe "error scenarios" do
  setup do
    SupervisorTestHelper.setup_crash_test_supervisor("error_test")
  end
  
  test "handles supervisor crashes", %{supervisor: supervisor} do
    # Supervisor designed to fail safely
  end
end
```

### Test Helper Architecture

#### SupervisorTestHelper (Core Infrastructure)

**`setup_isolated_supervisor/1`**
- Creates uniquely named supervisor instances
- Automatic cleanup with `on_exit/1`
- Essential for destructive tests

**`get_demo_supervisor/0`**
- Provides read-only access to shared supervisor
- Validates supervisor availability
- Fails fast if demo supervisor unavailable

**`wait_for_restart/2`**
- Uses GenServer calls for proper OTP synchronization
- Replaces anti-pattern of `Process.sleep/1`
- Deterministic waiting with timeout

**`wait_for_process_restart/3`**
- Monitors process death and restart
- Task-based timeout handling
- Robust error recovery

## Fundamental Design Patterns

### 1. Unique Process Naming

**Pattern:**
```elixir
unique_id = :erlang.unique_integer([:positive])
process_name = :"descriptive_base_name_#{unique_id}"
```

**For Helper Functions:**
```elixir
defp create_test_processes(count) do
  unique_id = :erlang.unique_integer([:positive])
  for i <- 1..count do
    process_name = :"test_process_#{i}_#{unique_id}"
    {:ok, pid} = MyProcess.start_link(name: process_name)
    pid
  end
end
```

**For Related Processes:**
```elixir
# Share unique_id within single test for related processes
unique_id = :erlang.unique_integer([:positive])
process_a = :"related_process_a_#{unique_id}"
process_b = :"related_process_b_#{unique_id}"
```

### 2. OTP-Compliant Synchronization

**✅ Correct Patterns:**

**Message Ordering Guarantee:**
```elixir
test "async operations" do
  GenServer.cast(pid, :message_1)
  GenServer.cast(pid, :message_2)
  # Synchronous call ensures all casts processed
  result = GenServer.call(pid, :get_state)
  assert result.count == 2
end
```

**Process Monitoring:**
```elixir
test "process termination" do
  ref = Process.monitor(pid)
  Process.exit(pid, :kill)
  
  receive do
    {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
  after
    1000 -> flunk("Process did not terminate")
  end
end
```

**Supervisor Restart Testing:**
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
  :ok = SupervisorTestHelper.wait_for_process_restart(:worker, original_pid)
  
  new_pid = Process.whereis(:worker)
  assert new_pid != original_pid
  assert Process.alive?(new_pid)
end
```

**❌ Anti-Patterns to Avoid:**

```elixir
# WRONG - Sleep-based synchronization
test "async operation" do
  GenServer.cast(pid, :do_something)
  Process.sleep(100)  # Flaky and un-OTP-like
  assert some_condition()
end

# WRONG - Internal state access
test "internal state" do
  state = :sys.get_state(pid)  # Accessing internals
  assert state.counter == 5
end

# WRONG - Hardcoded global names
test "process functionality" do
  {:ok, _} = MyProcess.start_link(name: :hardcoded_name)
  # Risk of conflicts
end
```

### 3. Proper Resource Cleanup

**Standard Cleanup Pattern:**
```elixir
setup do
  {:ok, pid} = MyProcess.start_link(name: unique_name)
  
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
  
  {:ok, pid: pid}
end
```

### 4. Error Handling and Suppression

**Surgical Error Suppression:**
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

**Comprehensive Error Testing:**
```elixir
test "error recovery behavior" do
  # Test error path
  assert {:error, :invalid_input} = MyProcess.handle_call(:invalid, pid)
  
  # Verify process still functional
  assert {:ok, result} = MyProcess.handle_call(:valid, pid)
  assert result == :expected_value
end
```

## Test Organization Standards

### 1. File Organization

**Test Directory Structure:**
```
test/
├── test_helper.exs              # Global configuration
├── support/                     # Test infrastructure
│   ├── supervisor_test_helper.ex
│   └── test_demo_supervisor.ex
├── [project_name]/              # Business logic tests
│   ├── core/                    # Core functionality
│   └── sandbox/                 # Sandboxed workers
└── [project_name]_web/          # Web layer tests
    ├── controllers/
    └── live/
```

### 2. Test Grouping by Behavior

**Organize by Isolation Requirements:**
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

### 3. Test Naming Conventions

**Descriptive Test Names:**
```elixir
test "supervisor restarts killed child with one_for_one strategy" do
  # Clear intent and educational value
end

test "concurrent operations maintain process state integrity" do
  # Explains the testing scenario
end
```

## Advanced Testing Patterns

### 1. Concurrent Operations Testing

**Pattern:**
```elixir
test "concurrent operations" do
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

### 2. Property-Based Testing

**StreamData Integration:**
```elixir
use ExUnit.Case
import StreamData

property "format_bytes handles any non-negative integer" do
  check all bytes <- integer(0..1_000_000_000) do
    formatted = MyModule.format_bytes(bytes)
    assert is_binary(formatted)
    assert formatted =~ ~r/\d+(\.\d+)?\s(B|KB|MB|GB|TB)/
  end
end
```

### 3. LiveView Testing Patterns

**Integration with Isolated Supervisors:**
```elixir
test "LiveView process operations", %{conn: conn} do
  %{supervisor: supervisor} = SupervisorTestHelper.setup_isolated_supervisor("lv_test")
  
  {:ok, view, _html} = live(conn, "/supervisors?supervisor=#{supervisor}")
  
  # Test UI operations with isolated processes
  view |> element("[data-test-kill-button]") |> render_click()
  
  # Assert on UI changes, not backend implementation
  html = render(view)
  assert html =~ "Process restarted"
end
```

## Implementation Workflow

### 1. Test Design Phase (Pre-Implementation)

**Design Checklist:**
- [ ] Identified test categories (destructive/read-only/error)
- [ ] Planned unique naming strategy
- [ ] Designed synchronization patterns
- [ ] Identified helper function requirements
- [ ] Planned error suppression approach

### 2. Implementation Phase

**Implementation Standards:**
- Use helper functions consistently
- Apply unique naming patterns
- Implement proper synchronization
- Add comprehensive cleanup
- Include educational comments

### 3. Validation Phase

**Validation Checklist:**
- [ ] All tests pass individually
- [ ] All tests pass in parallel
- [ ] No `Process.sleep/1` usage
- [ ] No hardcoded global names
- [ ] Helper functions used appropriately
- [ ] Educational value preserved

## Quality Assurance

### 1. Automated Validation

**CI/CD Integration:**
```bash
# Fail CI if Process.sleep found in tests
rg "Process\.sleep\(" test/ --type elixir && exit 1

# Fail CI if hardcoded global names found
rg "name: :[a-z_]+\b" test/ --type elixir | grep -v "unique_integer" && exit 1

# Run tests multiple times for race condition detection
for i in {1..3}; do
  mix test --seed $RANDOM || exit 1
done
```

### 2. Code Review Standards

**Review Checklist:**
- [ ] Appropriate test helper usage
- [ ] Consistent pattern application
- [ ] No global state dependencies
- [ ] Proper cleanup implementation
- [ ] Educational comments included

## Performance Considerations

### 1. Test Execution Speed

**Optimization Strategies:**
- Use `async: true` for isolated tests
- Minimize setup/teardown overhead
- Use shared resources for read-only tests
- Implement efficient helper functions

### 2. Resource Management

**Best Practices:**
- Proper process cleanup
- Efficient unique ID generation
- Minimal test data creation
- Optimized synchronization patterns

## Educational Integration

### 1. Tests as Documentation

**Documentation Standards:**
- Clear scenario descriptions
- Educational comments explaining OTP concepts
- Graduated complexity progression
- Real-world applicable examples

### 2. Learning Objectives

**Educational Focus:**
- Demonstrate proper OTP patterns
- Show supervision strategies
- Illustrate error handling
- Explain process lifecycle management

## Troubleshooting Guide

### Common Issues and Solutions

**Test Failures in Parallel:**
- Check for hardcoded global names
- Verify unique ID usage
- Ensure proper cleanup
- Look for shared mutable state

**Flaky Tests:**
- Replace `Process.sleep/1` with proper synchronization
- Use process monitoring
- Implement timeout handling
- Check for race conditions

**Helper Function Issues:**
- Ensure helpers generate unique names
- Verify helper cleanup patterns
- Check for helper-specific violations
- Validate helper usage consistency

## Summary

This reference provides comprehensive guidance for building robust, maintainable, and educational OTP tests. The key principles are:

1. **Test Independence**: Every test must be completely independent
2. **OTP Compliance**: Leverage OTP guarantees and patterns
3. **Educational Value**: Preserve and enhance learning objectives
4. **Systematic Approach**: Apply patterns consistently across all test types
5. **Continuous Improvement**: Learn from failures and refine patterns

By following these patterns and principles, teams can build test suites that are reliable, maintainable, and serve as excellent educational resources for understanding OTP application development.