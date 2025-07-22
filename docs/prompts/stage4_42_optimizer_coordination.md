# Stage 4.2: Optimizer Coordination Implementation

## Context

You are implementing the Optimizer Coordinator for the DSPex BridgedState backend. This component manages concurrent optimization processes, preventing conflicts and ensuring data consistency when multiple optimizers try to modify the same variables.

## Requirements

The Optimizer Coordinator must:

1. **Distributed Locking**: Prevent concurrent optimization of the same variable
2. **Conflict Resolution**: Handle multiple optimizers competing for resources
3. **Progress Tracking**: Monitor optimization progress and metrics
4. **Failure Handling**: Clean up locks when optimizers crash
5. **Preemption Support**: Allow high-priority optimizations to preempt others

## Implementation Guide

### 1. Create the Optimizer Coordinator Module

Create `lib/dspex/bridge/optimizer_coordinator.ex`:

```elixir
defmodule DSPex.Bridge.OptimizerCoordinator do
  @moduledoc """
  Coordinates multiple optimizers with distributed locking.
  
  This is a BridgedState-only feature that ensures optimization safety.
  Designed to support future distributed backends (Redis, etcd).
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :locks,              # var_id -> {optimizer_id, pid, acquired_at}
    :active_optimizations, # optimization_id -> details
    :conflict_queue,     # Queue of waiting lock requests
    :lock_timeout,       # Max time to hold a lock
    :metrics            # Performance metrics
  ]
end
```

### 2. Lock Management API

Design the public API for lock management:

```elixir
# Acquire an optimization lock
def acquire_lock(var_id, optimizer_id, optimizer_pid, opts \\ [])
# Options:
#   timeout: max time to wait for lock
#   conflict_resolution: :wait | :abort | :preempt
#   priority: integer priority for preemption

# Release an optimization lock
def release_lock(var_id, optimizer_id)

# Check if variable is locked
def is_locked?(var_id)

# Get lock info
def get_lock_info(var_id)

# Force release (admin operation)
def force_release(var_id, reason)
```

### 3. Optimization Tracking API

Track active optimizations:

```elixir
# Report optimization progress
def report_progress(optimization_id, iteration, current_value, metrics)

# Report optimization completion
def complete_optimization(optimization_id, final_value, final_metrics)

# Get optimization status
def get_optimization_status(optimization_id)

# List all active optimizations
def list_active_optimizations()

# Get optimization history
def get_optimization_history(var_id, limit \\ 10)
```

### 4. Conflict Resolution Strategies

Implement three conflict resolution strategies:

```elixir
# 1. Wait Strategy (default)
# - Queue the request
# - Process in FIFO order when lock released
# - Support timeout

# 2. Abort Strategy
# - Return immediately with error
# - Let caller decide what to do

# 3. Preempt Strategy
# - Compare priorities
# - If new > existing, notify existing optimizer
# - Force release after grace period
# - Grant to new optimizer
```

### 5. Lock State Machine

Each lock follows this state machine:

```
AVAILABLE -> ACQUIRED -> RELEASING -> AVAILABLE
               |
               v
           PREEMPTING -> FORCE_RELEASED -> AVAILABLE
```

### 6. Process Monitoring

Monitor optimizer processes:

```elixir
# When acquiring lock
Process.monitor(optimizer_pid)

# Handle process death
def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
  # Find all locks held by dead process
  # Clean them up
  # Process any queued requests
end
```

### 7. Stale Lock Detection

Implement automatic cleanup:

```elixir
# Schedule periodic cleanup
Process.send_after(self(), :cleanup_stale_locks, @cleanup_interval)

# Detect stale locks
defp is_stale?(lock, now) do
  now - lock.acquired_at > @lock_timeout
end

# Clean up with notification
defp cleanup_stale_lock(var_id, lock) do
  Logger.warning("Cleaning stale lock: #{var_id} held by #{lock.optimizer_id}")
  # Notify optimizer if still alive
  # Release lock
  # Process queue
end
```

### 8. Progress Tracking

Track optimization metrics:

```elixir
defstruct OptimizationInfo, [
  :id,
  :var_id,
  :optimizer_id,
  :started_at,
  :last_update,
  :iteration,
  :best_value,
  :best_metrics,
  :history  # Ring buffer of recent updates
]

# Determine if making progress
defp is_making_progress?(optimization) do
  # Check iteration advancement
  # Check metric improvement
  # Check time since last update
end
```

### 9. Telemetry Events

Emit comprehensive telemetry:

```elixir
# Lock acquired
:telemetry.execute(
  [:dspex, :optimization, :lock_acquired],
  %{wait_time_ms: wait_time},
  %{var_id: var_id, optimizer_id: optimizer_id}
)

# Lock conflict
:telemetry.execute(
  [:dspex, :optimization, :lock_conflict],
  %{},
  %{var_id: var_id, holder: existing_id, requester: new_id}
)

# Optimization progress
:telemetry.execute(
  [:dspex, :optimization, :progress],
  %{iteration: iteration, metrics: metrics},
  %{optimization_id: id, var_id: var_id}
)

# Lock preempted
:telemetry.execute(
  [:dspex, :optimization, :preempted],
  %{held_duration_ms: duration},
  %{var_id: var_id, preempted: old_id, preemptor: new_id}
)
```

### 10. Integration with SessionStore

Coordinate with SessionStore:

```elixir
# Before variable update
case OptimizerCoordinator.check_write_allowed(var_id, writer_id) do
  :ok -> 
    # Proceed with update
  {:error, {:locked_by, other_id}} ->
    # Handle based on policy
end

# Register optimization session
def start_optimization_session(session_id, var_ids, optimizer_config)

# Batch lock acquisition
def acquire_locks(var_ids, optimizer_id, opts)
```

### 11. Testing Scenarios

Test these critical scenarios:

1. **Basic Locking**:
   - Single lock acquire/release
   - Multiple variables locked by same optimizer
   - Lock timeout and cleanup

2. **Conflict Resolution**:
   - Wait queue processing
   - Abort on conflict
   - Priority-based preemption

3. **Failure Handling**:
   - Optimizer crash during optimization
   - Network partition simulation
   - Partial lock acquisition failure

4. **Performance**:
   - High contention scenarios
   - Lock acquisition latency
   - Queue processing throughput

### 12. Example Usage

```elixir
# Start optimization
{:ok, lock_token} = OptimizerCoordinator.acquire_lock(
  "var_model_weights",
  "optimizer_123",
  self(),
  conflict_resolution: :wait,
  timeout: 30_000
)

# Report progress during optimization
for iteration <- 1..100 do
  new_weights = optimize_step(current_weights)
  metrics = %{loss: loss, accuracy: acc}
  
  OptimizerCoordinator.report_progress(
    "optimizer_123",
    iteration,
    new_weights,
    metrics
  )
end

# Complete optimization
OptimizerCoordinator.complete_optimization(
  "optimizer_123",
  final_weights,
  final_metrics
)

# Release lock
OptimizerCoordinator.release_lock("var_model_weights", "optimizer_123")
```

### 13. Advanced Features

Design for future enhancements:

1. **Distributed Locking**: Redis/etcd backend support
2. **Lock Hierarchies**: Parent locks imply child locks
3. **Read/Write Locks**: Multiple readers, single writer
4. **Lock Leasing**: Time-based automatic expiry
5. **Deadlock Detection**: Multi-variable lock ordering

## Implementation Checklist

- [ ] Create OptimizerCoordinator GenServer
- [ ] Implement basic lock acquire/release
- [ ] Add process monitoring for crash cleanup
- [ ] Implement conflict resolution strategies
- [ ] Add progress tracking and metrics
- [ ] Create stale lock detection
- [ ] Implement preemption mechanism
- [ ] Add comprehensive telemetry
- [ ] Integrate with SessionStore
- [ ] Write unit tests for all scenarios
- [ ] Add integration tests
- [ ] Create performance benchmarks
- [ ] Document lock semantics

## Success Criteria

1. **Safety**: No concurrent modifications of locked variables
2. **Liveness**: No deadlocks or permanently stuck locks
3. **Fairness**: Requests processed in predictable order
4. **Performance**: Sub-millisecond lock operations
5. **Observability**: Complete visibility into lock state
6. **Resilience**: Automatic recovery from failures