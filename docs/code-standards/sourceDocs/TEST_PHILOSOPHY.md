# Foundation Test Philosophy - Event-Driven Deterministic Testing

## Core Philosophy: The System Should Tell Us When It's Ready

**Fundamental Principle**: Tests should wait for the system to explicitly signal completion rather than guessing how long operations take.

> "A test that uses `Process.sleep/1` is a test that doesn't understand what it's waiting for."

## The Anti-Pattern: Process.sleep-Based Testing

### What We're Fighting Against

**Sleep-Based Testing** represents a fundamental misunderstanding of asynchronous systems:

```elixir
# ANTI-PATTERN: Guessing completion times
test "service restarts after crash" do
  pid = Process.whereis(MyService)
  Process.exit(pid, :kill)
  Process.sleep(200)  # 🚨 GUESS: "200ms should be enough"
  
  new_pid = Process.whereis(MyService)
  assert new_pid != pid
end
```

**Problems with this approach**:
- **Unreliable**: Works on developer machine, fails in CI under load
- **Slow**: Forces unnecessary waiting even when operation completes in 5ms
- **Flaky**: Different system loads produce different timing
- **Masks Issues**: Hides race conditions instead of exposing them
- **Non-Deterministic**: Same test can pass or fail based on timing luck

### The Cognitive Failure

Sleep-based testing indicates **we don't understand our own system**:
- We don't know when the operation actually completes
- We don't know what signals indicate completion
- We don't trust our system's ability to communicate its state
- We resort to "magical thinking" about timing

## The Solution: Event-Driven Testing

### Principle 1: Observable Operations

**Every operation should emit events** that indicate its lifecycle:

```elixir
# CORRECT: Event-driven testing
test "service restarts after crash" do
  pid = Process.whereis(MyService)
  
  # Wait for the explicit restart event
  assert_telemetry_event [:foundation, :service, :restarted],
    %{service: MyService, new_pid: new_pid} do
    Process.exit(pid, :kill)
  end
  
  # Guaranteed: service has restarted
  assert new_pid != pid
  assert Process.alive?(new_pid)
end
```

**Benefits**:
- **Deterministic**: Completes as soon as event occurs
- **Fast**: No arbitrary delays
- **Reliable**: Works under any system load  
- **Clear**: Expresses exactly what we're waiting for
- **Exposes Issues**: Real race conditions become apparent

### Principle 2: System Self-Description

**The system should describe its own state changes** rather than tests guessing:

```elixir
# System emits: [:foundation, :circuit_breaker, :state_change]
# Test listens: assert_telemetry_event [:foundation, :circuit_breaker, :state_change]

# System emits: [:foundation, :async, :completed] 
# Test listens: assert_telemetry_event [:foundation, :async, :completed]

# System emits: [:foundation, :resource, :cleanup_finished]
# Test listens: assert_telemetry_event [:foundation, :resource, :cleanup_finished]
```

### Principle 3: Explicit Dependencies

**Tests should explicitly wait for their dependencies** rather than hoping timing works out:

```elixir
# WRONG: Hope both operations complete in time
test "complex workflow" do
  start_async_operation_1()
  start_async_operation_2()  
  Process.sleep(500)  # 🚨 Hope both finished
  verify_combined_result()
end

# RIGHT: Wait for explicit completion of each dependency
test "complex workflow" do
  assert_telemetry_event [:app, :operation_1, :completed], %{} do
    start_async_operation_1()
  end
  
  assert_telemetry_event [:app, :operation_2, :completed], %{} do
    start_async_operation_2()
  end
  
  # Both operations guaranteed complete
  verify_combined_result()
end
```

## Testing Categories and Strategies

### Category 1: Standard Async Operations (95% of cases)

**Rule**: Use event-driven coordination

**Examples**:
- Service startup/shutdown
- Process restarts  
- Background task completion
- State machine transitions
- Resource allocation/cleanup
- Circuit breaker state changes
- Agent coordination

**Pattern**:
```elixir
test "operation completes correctly" do
  assert_telemetry_event [:system, :operation, :completed], expected_metadata do
    trigger_async_operation()
  end
  
  verify_final_state()
end
```

### Category 2: Testing Telemetry System Itself (2% of cases)

**Rule**: Use telemetry capture patterns

**Challenge**: Can't wait for events when testing event emission itself

**Pattern**:
```elixir
test "system emits correct events" do
  events = capture_telemetry [:system, :operation] do
    perform_operation()
  end
  
  assert length(events) == 2
  assert Enum.any?(events, fn {event, metadata} ->
    event == [:system, :operation, :started]
  end)
end
```

### Category 3: External System Integration (2% of cases)

**Rule**: Limited use of minimal delays acceptable

**Challenge**: External systems don't emit our telemetry events

**Pattern**:
```elixir
test "external API integration" do
  trigger_external_call()
  
  # Acceptable: Minimal delay for external systems we don't control
  :timer.sleep(100)  # Better than Process.sleep
  
  # Or better: Polling with timeout
  wait_for(fn -> ExternalSystem.ready?() end, 2000)
end
```

### Category 4: Time-Based Business Logic (1% of cases)

**Rule**: Delay IS the feature being tested

**Examples**: Rate limiting, timeouts, scheduled operations

**Pattern**:
```elixir
test "rate limiter resets after window" do
  # Fill the rate limit bucket
  fill_rate_limit_bucket()
  assert :denied = RateLimiter.check(user_id)
  
  # Wait for reset window (this IS the feature)  
  :timer.sleep(rate_limit_window_ms + 10)
  
  # Should be reset now
  assert :allowed = RateLimiter.check(user_id)
end
```

## Advanced Testing Patterns

### Pattern 1: Event Sequences

**For complex workflows with multiple async steps**:

```elixir
test "distributed agent coordination" do
  agents = ["agent_1", "agent_2", "agent_3"]
  
  # Wait for entire sequence of coordination events
  assert_telemetry_sequence [
    {[:mabeam, :coordination, :started], %{agents: ^agents}},
    {[:mabeam, :coordination, :sync_point], %{phase: 1}},
    {[:mabeam, :coordination, :sync_point], %{phase: 2}},
    {[:mabeam, :coordination, :completed], %{result: :success}}
  ] do
    MABEAM.coordinate_agents(agents, :complex_task)
  end
  
  # All agents guaranteed to be in final state
  for agent <- agents do
    assert {:ok, :idle} = MABEAM.get_agent_status(agent)
  end
end
```

### Pattern 2: Conditional Events

**For operations that may succeed or fail**:

```elixir
test "circuit breaker opens on threshold" do
  service_id = "test_service"
  
  # Wait for either success or circuit opening
  assert_telemetry_any [
    {[:foundation, :circuit_breaker, :state_change], %{to: :open}},
    {[:foundation, :circuit_breaker, :call_success], %{}}
  ] do
    # Generate load that should trip circuit breaker
    generate_load(service_id, failure_rate: 0.8)
  end
  
  # React based on which event occurred
  case CircuitBreaker.get_status(service_id) do
    {:ok, :open} -> assert_circuit_breaker_behavior()
    {:ok, :closed} -> assert_successful_operation()
  end
end
```

### Pattern 3: Performance-Based Coordination

**For operations where completion is indicated by performance metrics**:

```elixir
test "system reaches steady state performance" do
  start_system_under_load()
  
  # Wait for performance to stabilize
  wait_for_metric_threshold("response_time_p95", 100, timeout: 30_000)
  wait_for_metric_threshold("error_rate", 0.01, timeout: 30_000)
  
  # System guaranteed to be in steady state
  verify_steady_state_behavior()
end
```

## Error Patterns and Solutions

### Error Pattern 1: "It works on my machine"

**Symptom**: Tests pass locally but fail in CI

**Root Cause**: Sleep durations tuned for developer machine performance

**Solution**: Replace with event-driven coordination
```elixir
# WRONG: Tuned for local machine
Process.sleep(50)  # Works locally, fails in CI

# RIGHT: Works everywhere
assert_telemetry_event [:system, :ready], %{}
```

### Error Pattern 2: "Flaky tests"

**Symptom**: Tests sometimes pass, sometimes fail  

**Root Cause**: Race conditions masked by arbitrary delays

**Solution**: Expose and fix the race condition
```elixir
# WRONG: Masks race condition
async_operation()
Process.sleep(100)  # Sometimes not enough
verify_result()

# RIGHT: Exposes race condition, forces proper fix
assert_telemetry_event [:system, :operation, :completed], %{} do
  async_operation()
end
verify_result()  # If this fails, there's a real bug to fix
```

### Error Pattern 3: "Slow test suite"

**Symptom**: Test suite takes minutes to run

**Root Cause**: Cumulative sleep delays

**Solution**: Event-driven testing eliminates unnecessary waiting
```elixir
# WRONG: 2000ms of forced waiting per test
Process.sleep(2000)

# RIGHT: Completes in 5-50ms typically  
assert_telemetry_event [:system, :ready], %{}
```

## Implementation Guidelines

### Guideline 1: Start with Event Design

**Before writing the test**, design the events:

1. What operation am I testing?
2. What events should this operation emit?
3. What metadata indicates successful completion?
4. What events indicate failure modes?

### Guideline 2: Test-Driven Event Design

**Let test requirements drive telemetry design**:

```elixir
# If the test needs this event...
assert_telemetry_event [:myapp, :user, :registered], %{user_id: user_id}

# Then the implementation must emit it
def register_user(user_params) do
  # ... registration logic ...
  
  :telemetry.execute([:myapp, :user, :registered], %{}, %{
    user_id: user.id,
    timestamp: DateTime.utc_now()
  })
  
  {:ok, user}
end
```

### Guideline 3: Fail Fast on Missing Events

**Make missing events obvious**:

```elixir
# Use reasonable timeouts that fail fast
assert_telemetry_event [:system, :ready], %{}, timeout: 1000

# Better to fail fast than wait forever
# If event doesn't occur in 1 second, something is wrong
```

### Guideline 4: Comprehensive Event Coverage

**Emit events for all significant operations**:

- Process startup/shutdown
- State transitions
- Resource allocation/deallocation  
- External system calls
- Error conditions
- Performance milestones
- Configuration changes

## Metrics and Success Criteria

### Test Suite Health Metrics

- **Sleep Usage**: Target 0 instances of `Process.sleep/1` in tests
- **Flaky Test Rate**: Target <0.1% flaky test failures
- **Test Suite Speed**: Target 50%+ faster execution
- **Coverage**: 95%+ of async operations have event-driven tests

### Code Quality Metrics

- **Event Coverage**: All services emit operational telemetry
- **Test Clarity**: Tests clearly express what they're waiting for
- **Determinism**: Tests pass reliably under load
- **Maintainability**: New developers can understand test intent

## Anti-Pattern Detection

### Code Review Checklist

- [ ] No `Process.sleep/1` in test files (exceptions documented)
- [ ] Async operations have corresponding telemetry events
- [ ] Tests use `assert_telemetry_event` instead of arbitrary delays
- [ ] Event-driven patterns used for all async coordination
- [ ] Fallback patterns documented for edge cases

### Automated Detection

**Credo Rule**: Ban `Process.sleep/1` in test files
**CI Check**: Fail builds with sleep-based tests
**Metrics**: Track event-driven test adoption rate

## Philosophy Summary

### Core Beliefs

1. **Systems should be self-describing** - Operations emit events describing their lifecycle
2. **Tests should be deterministic** - Wait for specific conditions, not arbitrary time
3. **Async operations need async coordination** - Event-driven patterns for async testing
4. **Race conditions should be exposed, not hidden** - Proper synchronization over timing luck
5. **Fast feedback loops** - Tests complete as soon as conditions are met

### The Goal

**Transform testing from "guessing game" to "conversation with the system"**:

- Instead of guessing timing, listen to system events
- Instead of hoping for completion, wait for explicit signals  
- Instead of masking race conditions, expose and fix them
- Instead of slow, unreliable tests, fast, deterministic verification

When we achieve this, testing becomes a **conversation between the test and the system**, where the system explicitly tells us when it's ready for the next assertion. This creates tests that are fast, reliable, clear, and maintainable.

---

*Foundation Test Philosophy*  
*Event-Driven Deterministic Testing*  
*"The system should tell us when it's ready"*