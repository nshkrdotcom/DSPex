# Pool V2 Migration Guide

## Overview

This guide describes how to migrate from the current SessionPool/PoolWorker implementation (V1) to the refactored V2 implementation that properly implements the NimblePool pattern for true concurrent execution.

## Why Migrate?

### V1 Problems
- **Serialized Execution**: All operations go through SessionPool GenServer, creating a bottleneck
- **No True Concurrency**: Despite having a pool, operations execute one at a time
- **Poor Performance**: High latency for concurrent requests due to queueing

### V2 Benefits
- **True Concurrency**: Operations execute in parallel in client processes
- **Better Performance**: N-fold throughput improvement (N = pool size)
- **Proper NimblePool Pattern**: Follows documented best practices
- **Simplified Architecture**: Cleaner separation of concerns

## Migration Strategy

### Phase 1: Parallel Implementation (Week 1)

1. **Keep V1 Running**: Don't modify existing code initially
2. **Deploy V2 Modules**: Add new modules alongside existing ones:
   - `SessionPoolV2`
   - `PoolWorkerV2`
   - `PythonPoolV2`

3. **Configuration Switch**: Add config to choose implementation:
   ```elixir
   config :dspex,
     pool_version: :v1  # or :v2
   ```

4. **Adapter Registry Update**: Modify registry to return correct adapter:
   ```elixir
   def get_adapter do
     case Application.get_env(:dspex, :pool_version, :v1) do
       :v1 -> DSPex.Adapters.PythonPool
       :v2 -> DSPex.Adapters.PythonPoolV2
     end
   end
   ```

### Phase 2: Testing & Validation (Week 2)

1. **Unit Tests**: Run both V1 and V2 tests in parallel
2. **Integration Tests**: Add tests that verify V2 behavior
3. **Performance Tests**: Benchmark V1 vs V2 performance
4. **Load Tests**: Verify V2 handles high concurrency correctly

### Phase 3: Gradual Rollout (Week 3)

1. **Development Environment**: Switch dev to V2 first
2. **Staging Environment**: Run V2 for subset of operations
3. **Production Canary**: Route small % of traffic to V2
4. **Monitor Metrics**: Track performance and error rates

### Phase 4: Full Migration (Week 4)

1. **Switch Default**: Change default from V1 to V2
2. **Deprecation Notice**: Mark V1 as deprecated
3. **Final Validation**: Ensure all systems using V2
4. **Cleanup**: Remove V1 code after burn-in period

## Code Changes Required

### Supervisor Configuration

Update `PoolSupervisor` to conditionally start V1 or V2:

```elixir
defmodule DSPex.PythonBridge.PoolSupervisor do
  def init(_args) do
    children = case Application.get_env(:dspex, :pool_version, :v1) do
      :v1 ->
        [{DSPex.PythonBridge.SessionPool, 
          pool_size: pool_size,
          overflow: overflow,
          name: DSPex.PythonBridge.SessionPool}]
      
      :v2 ->
        [{DSPex.PythonBridge.SessionPoolV2,
          pool_size: pool_size,
          overflow: overflow,
          name: DSPex.PythonBridge.SessionPoolV2}]
    end
    
    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

### Application Code

No changes required! The adapter interface remains the same:

```elixir
# This code works with both V1 and V2
adapter = DSPex.Adapters.Registry.get_adapter()
{:ok, program_id} = adapter.create_program(config)
{:ok, result} = adapter.execute_program(program_id, inputs)
```

### Test Updates

Add environment variable to control which version tests run:

```elixir
# In test_helper.exs
if System.get_env("POOL_VERSION") == "v2" do
  Application.put_env(:dspex, :pool_version, :v2)
end
```

Run tests for both versions:
```bash
# Test V1
mix test

# Test V2
POOL_VERSION=v2 mix test
```

## Monitoring & Rollback

### Key Metrics to Monitor

1. **Performance Metrics**
   - Request latency (p50, p95, p99)
   - Throughput (requests/second)
   - Pool utilization
   - Worker creation/destruction rate

2. **Error Metrics**
   - Error rates by type
   - Timeout rates
   - Worker crash rates

3. **Resource Metrics**
   - Memory usage
   - CPU usage
   - Port/file descriptor usage

### Rollback Plan

If issues arise, rollback is simple:

1. **Immediate**: Change config from `:v2` to `:v1`
2. **Restart**: Restart application to pick up config
3. **Verify**: Confirm V1 is active via stats/logs

## Validation Checklist

Before considering migration complete:

- [ ] All unit tests pass for V2
- [ ] Integration tests show correct concurrent behavior
- [ ] Performance benchmarks show improvement
- [ ] Load tests pass without errors
- [ ] Session isolation verified
- [ ] Error handling works correctly
- [ ] Monitoring shows stable metrics
- [ ] No increase in error rates
- [ ] Memory usage is stable
- [ ] Documentation updated

## Common Issues & Solutions

### Issue: "module not found" errors
**Solution**: Ensure V2 modules are compiled and included in release

### Issue: Different error messages between V1/V2
**Solution**: Update error handling to normalize messages

### Issue: Session tracking differences
**Solution**: Ensure ETS table is properly initialized

### Issue: Performance regression in specific scenarios
**Solution**: Check pool size configuration and timeout settings

## Post-Migration

After successful migration:

1. **Remove V1 Code**: After 2-4 weeks of stable operation
2. **Update Documentation**: Remove references to V1
3. **Simplify Configuration**: Remove version switching logic
4. **Optimize Further**: Tune pool parameters based on production data

## Support

For migration support:
- Check logs for migration-related messages
- Monitor the `:dspex` application metrics
- Review error reports for V2-specific issues

The migration is designed to be safe and reversible at any point.