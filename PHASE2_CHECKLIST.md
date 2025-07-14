# Phase 2: Worker Lifecycle Management - Implementation Checklist

## Overview
Phase 2 focuses on implementing proper worker lifecycle management, including state machines, health monitoring, and graceful shutdown mechanisms.

## New Files to Create

1. **lib/dspex/python_bridge/pool_worker_state.ex**
   - Purpose: Define worker state machine with proper state transitions
   - States: :initializing, :ready, :busy, :draining, :terminated

2. **lib/dspex/python_bridge/pool_health_monitor.ex**
   - Purpose: Monitor worker health and trigger recycling when needed
   - Features: Periodic health checks, error tracking, automatic recovery

3. **test/pool_worker_lifecycle_test.exs**
   - Purpose: Comprehensive tests for worker lifecycle transitions
   - Coverage: State transitions, health checks, recycling policies

## Existing Files to Modify

1. **lib/dspex/python_bridge/pool_worker_v2.ex**
   - Expected changes:
     - Integrate state machine for proper lifecycle management
     - Add health check callbacks
     - Implement graceful shutdown with session draining
     - Add worker recycling based on age/usage

2. **lib/dspex/python_bridge/session_pool_v2.ex**
   - Expected changes:
     - Track worker states in pool metadata
     - Implement worker recycling policies
     - Add health monitoring integration
     - Handle worker state transitions

3. **lib/dspex/python_bridge/pool_supervisor_v2.ex**
   - Expected changes:
     - Add health monitor to supervision tree
     - Configure restart strategies for different failure modes
     - Implement progressive backoff for worker restarts

## Tests to Write

1. **Worker State Transition Tests**
   - Test all valid state transitions
   - Verify invalid transitions are rejected
   - Test concurrent state changes

2. **Health Monitoring Tests**
   - Worker health check success/failure scenarios
   - Automatic recycling triggers
   - Health status reporting

3. **Graceful Shutdown Tests**
   - Session draining during shutdown
   - Timeout handling for long-running operations
   - Clean resource cleanup

4. **Worker Recycling Tests**
   - Age-based recycling
   - Usage-based recycling
   - Error threshold recycling
   - Pool size maintenance during recycling

## Dependencies on Phase 1

All Phase 1 fixes are complete and required for Phase 2:
- ✅ NimblePool return values fixed
- ✅ Port validation implemented
- ✅ Test assertions corrected
- ✅ Test guards added
- ✅ Service detection improved

## Main Risk Areas

1. **State Synchronization**
   - Challenge: Keeping worker state consistent between pool and worker process
   - Mitigation: Use gen_statem or similar for strict state management

2. **Race Conditions**
   - Challenge: Worker might change state during checkout/checkin
   - Mitigation: Proper locking and atomic state transitions

3. **Resource Leaks**
   - Challenge: Ensuring ports and processes are cleaned up properly
   - Mitigation: Comprehensive cleanup in terminate callbacks

4. **Performance Impact**
   - Challenge: Health checks and state tracking add overhead
   - Mitigation: Configurable check intervals, efficient state storage

5. **Backward Compatibility**
   - Challenge: Maintaining compatibility with existing pool users
   - Mitigation: Keep external API unchanged, internal refactoring only

## Success Criteria

1. Workers transition through states correctly
2. Unhealthy workers are automatically recycled
3. Graceful shutdown completes within timeout
4. No resource leaks during normal operation
5. Pool maintains target size during recycling
6. All existing tests continue to pass

## Implementation Order

1. Implement worker state machine
2. Add health monitoring
3. Implement graceful shutdown
4. Add worker recycling policies
5. Comprehensive testing
6. Performance optimization

## Configuration Options to Add

```elixir
config :dspex, :pool_worker_lifecycle,
  health_check_interval: 30_000,      # 30 seconds
  max_worker_age: 3_600_000,          # 1 hour
  max_worker_requests: 1000,          # requests before recycling
  error_threshold: 5,                 # errors before recycling
  shutdown_timeout: 30_000,           # 30 seconds for graceful shutdown
  enable_health_monitoring: true      # can be disabled for testing
```