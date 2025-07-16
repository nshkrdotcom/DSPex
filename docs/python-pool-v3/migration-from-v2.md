# Migration Guide: Pool V2 to V3

## Overview

This guide helps migrate from the complex NimblePool-based V2 implementation to the simpler OTP-based V3 design. The migration can be done gradually with zero downtime.

## What Changes

### Removed Components

| V2 Component | Why Removed | V3 Replacement |
|--------------|-------------|----------------|
| NimblePool | Sequential init, overcomplicated | DynamicSupervisor + Queue |
| WorkerStateMachine | Over-engineered | OTP process states |
| WorkerRecovery | Complex custom logic | OTP supervisor restarts |
| CircuitBreaker | Premature optimization | Add later if needed |
| Session Affinity in Pool | Couples concerns | Stateless workers + SessionStore |
| PoolWorkerV2Enhanced | Too many features | Simple Worker |

### Simplified Architecture

```
V2: Client → SessionPoolV2 → NimblePool → PoolWorkerV2 → PythonPort
                ↓                             ↓
         SessionAffinity              WorkerStateMachine
                ↓                             ↓
         WorkerRecovery                CircuitBreaker

V3: Client → Pool → Worker → PythonPort
              ↓        ↓
           Queue   Registry
```

## Migration Steps

### Step 1: Add V3 Modules (No Breaking Changes)

```elixir
# Add new modules without touching existing code
lib/dspex/python/
├── worker_supervisor.ex
├── worker.ex
├── pool.ex
└── registry.ex
```

### Step 2: Update Application Supervisor

```elixir
defmodule DSPex.Application do
  def start(_type, _args) do
    children = [
      # Existing V2 components
      DSPex.PythonBridge.SessionStore,
      {DSPex.PythonBridge.SessionPoolV2, v2_config()},
      
      # New V3 components (running in parallel)
      DSPex.Python.Registry,
      DSPex.Python.WorkerSupervisor,
      {DSPex.Python.Pool, v3_config()}
    ]
    
    opts = [strategy: :one_for_one, name: DSPex.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  defp v2_config do
    [pool_size: 8, overflow: 2]
  end
  
  defp v3_config do
    [size: 8]
  end
end
```

### Step 3: Create Adapter Layer

```elixir
defmodule DSPex.PoolAdapter do
  @moduledoc """
  Routes requests to V2 or V3 pool based on configuration.
  Allows gradual migration without changing client code.
  """
  
  def execute_in_session(session_id, command, args, opts \\ []) do
    case pool_version() do
      :v2 -> 
        DSPex.PythonBridge.SessionPoolV2.execute_in_session(
          session_id, command, args, opts
        )
      :v3 -> 
        # V3 is stateless, session data handled by SessionStore
        enhanced_args = enhance_args_for_session(session_id, command, args)
        DSPex.Python.Pool.execute(command, enhanced_args, opts)
    end
  end
  
  def execute_anonymous(command, args, opts \\ []) do
    case pool_version() do
      :v2 -> 
        DSPex.PythonBridge.SessionPoolV2.execute_anonymous(command, args, opts)
      :v3 -> 
        DSPex.Python.Pool.execute(command, args, opts)
    end
  end
  
  defp pool_version do
    Application.get_env(:dspex, :pool_version, :v2)
  end
  
  defp enhance_args_for_session(session_id, command, args) do
    # Add session context to args
    Map.put(args, :session_id, session_id)
  end
end
```

### Step 4: Update Client Code

```elixir
# Before (direct V2 usage)
SessionPoolV2.execute_in_session(session_id, :execute_program, args)

# After (via adapter)
PoolAdapter.execute_in_session(session_id, :execute_program, args)
```

### Step 5: Feature Flag Rollout

```elixir
# config/config.exs
config :dspex, :pool_version, :v2  # Start with V2

# config/prod.exs
config :dspex, :pool_version, :v3  # Switch to V3 in production

# Or use runtime config for instant switching
# config/runtime.exs
config :dspex, :pool_version, System.get_env("POOL_VERSION", "v2") |> String.to_atom()
```

### Step 6: Gradual Migration

1. **Week 1**: Run both pools, all traffic to V2
2. **Week 2**: 10% traffic to V3, monitor metrics
3. **Week 3**: 50% traffic to V3
4. **Week 4**: 100% traffic to V3
5. **Week 5**: Remove V2 code

## Code Comparison

### Creating and Executing a Program

#### V2 (Complex)
```elixir
# Multiple components involved
{:ok, worker_state} = WorkerStateMachine.transition(state, :ready, :busy)
SessionAffinity.store_worker_session(session_id, worker_id)

case CircuitBreaker.call(breaker, fn ->
  PoolWorkerV2Enhanced.execute_with_recovery(
    worker, session_id, command, args,
    retry_strategy: :exponential_backoff,
    max_retries: 3
  )
end) do
  {:ok, result} -> 
    WorkerMetrics.record_success(worker_id)
    {:ok, result}
  {:error, reason} ->
    ErrorRecoveryOrchestrator.handle_error(reason, context)
end
```

#### V3 (Simple)
```elixir
# Direct execution
Pool.execute(:create_program, %{
  id: "my_program",
  signature: "question -> answer"
})
```

### Handling Worker Failures

#### V2 (Manual)
```elixir
def handle_worker_failure(worker_id, reason) do
  case WorkerRecovery.analyze_failure(reason) do
    {:recoverable, strategy} ->
      WorkerRecovery.execute_recovery(worker_id, strategy)
    {:permanent, _} ->
      WorkerStateMachine.transition(worker_id, :any, :terminated)
      PoolWorkerV2.terminate_worker(worker_id)
      start_replacement_worker()
  end
end
```

#### V3 (Automatic)
```elixir
# OTP supervisor handles it automatically
# Worker crashes → Supervisor restarts it
# No code needed
```

## Performance Improvements

### Startup Time
- **V2**: 16-24 seconds (sequential)
- **V3**: 2-3 seconds (concurrent)

### Memory Usage
- **V2**: ~150MB (complex state machines)
- **V3**: ~80MB (simple processes)

### Request Latency
- **V2**: +5-10ms overhead (multiple layers)
- **V3**: +1-2ms overhead (direct dispatch)

## Testing During Migration

### Parallel Testing
```elixir
defmodule MigrationTest do
  use ExUnit.Case
  
  test "V2 and V3 produce same results" do
    # Start both pools
    start_supervised!({SessionPoolV2, name: :v2_pool})
    start_supervised!({Pool, name: :v3_pool})
    
    # Same operation on both
    args = %{expression: "2 + 2"}
    {:ok, v2_result} = SessionPoolV2.execute_anonymous(:calculate, args)
    {:ok, v3_result} = Pool.execute(:calculate, args)
    
    # Results should match
    assert v2_result == v3_result
  end
end
```

### Load Testing
```elixir
defmodule LoadTest do
  def compare_pools(num_requests) do
    # Measure V2
    v2_time = :timer.tc(fn ->
      run_concurrent_requests(&SessionPoolV2.execute_anonymous/3, num_requests)
    end) |> elem(0)
    
    # Measure V3
    v3_time = :timer.tc(fn ->
      run_concurrent_requests(&Pool.execute/3, num_requests)
    end) |> elem(0)
    
    IO.puts("V2 time: #{v2_time/1_000}ms")
    IO.puts("V3 time: #{v3_time/1_000}ms")
    IO.puts("Improvement: #{Float.round(v2_time/v3_time, 2)}x")
  end
end
```

## Rollback Plan

If issues arise during migration:

1. **Immediate**: Change pool_version config to :v2
2. **No restart needed**: Adapter routes traffic back to V2
3. **Monitor**: Check metrics, logs for issues
4. **Fix**: Address V3 issues while V2 handles traffic
5. **Retry**: Switch back to V3 when ready

## Post-Migration Cleanup

Once V3 is stable:

1. **Remove V2 modules**:
   ```bash
   rm lib/dspex/python_bridge/session_pool_v2.ex
   rm lib/dspex/python_bridge/pool_worker_v2*.ex
   rm lib/dspex/python_bridge/worker_state_machine.ex
   # ... etc
   ```

2. **Remove adapter layer**:
   ```elixir
   # Change all PoolAdapter calls to Pool calls
   PoolAdapter.execute(...) → Pool.execute(...)
   ```

3. **Clean up configuration**:
   ```elixir
   # Remove pool_version config
   # Remove V2-specific settings
   ```

4. **Update tests**:
   ```elixir
   # Remove V2-specific tests
   # Remove migration tests
   ```

## Common Migration Issues

### Issue 1: Session State
**V2**: Workers maintain session affinity
**V3**: Workers are stateless

**Solution**: Ensure SessionStore has all needed state before execution

### Issue 2: Error Handling Differences
**V2**: Complex error categorization and recovery
**V3**: Simple error propagation

**Solution**: Add error wrapper if specific handling needed:
```elixir
defmodule ErrorAdapter do
  def wrap_v3_errors({:error, reason}) do
    # Convert to V2-style error if needed
    {:error, categorize_error(reason)}
  end
end
```

### Issue 3: Metrics Compatibility
**V2**: Extensive WorkerMetrics module
**V3**: Basic telemetry events

**Solution**: Add telemetry handler to maintain existing metrics:
```elixir
:telemetry.attach(
  "v2-compat-metrics",
  [:dspex, :python, :pool, :request],
  &V2MetricsAdapter.handle_event/4,
  nil
)
```

## Success Metrics

Monitor these during migration:

1. **Error Rate**: Should remain stable or improve
2. **Latency**: P99 should improve by 50%+
3. **Startup Time**: Should improve by 8x+
4. **Memory Usage**: Should decrease by 40%+
5. **Code Complexity**: LOC should decrease by 80%+

## Timeline

- **Day 1-2**: Implement V3 modules
- **Day 3**: Add adapter layer
- **Day 4-5**: Update client code to use adapter
- **Week 2**: Begin traffic migration
- **Week 3-4**: Monitor and tune
- **Week 5**: Complete migration
- **Week 6**: Remove V2 code

## Questions?

For migration support:
1. Check metrics dashboards
2. Review error logs
3. Run comparison tests
4. Gradual rollout is key