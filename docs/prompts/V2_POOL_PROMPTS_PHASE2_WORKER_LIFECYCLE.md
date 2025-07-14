# V2 Pool Implementation Prompts - Phase 2: Worker Lifecycle Management

## Session 2.1: Worker State Machine Implementation

### Prompt 2.1.1 - Create State Machine Module
```
We're implementing Phase 2 of the V2 Pool design, specifically the Worker State Machine.
Current status: Phase 1 fixes complete and tested
Today's goal: Implement the complete WorkerStateMachine module

Create lib/dspex/python_bridge/worker_state_machine.ex from Design Doc 3. Start with the type definitions, struct, and new/1 function. Show me the initial implementation.
```

### Prompt 2.1.2 - Implement State Transitions
```
Now implement the transition/4 function and the private do_transition/4 function in WorkerStateMachine.

Ensure it:
1. Validates transitions against @valid_transitions
2. Records transition history with timestamps
3. Logs all transitions
4. Returns proper error for invalid transitions

Show the complete implementation.
```

### Prompt 2.1.3 - Add Helper Functions
```
Add the remaining helper functions to WorkerStateMachine:
1. can_accept_work?/1 - checks if worker can accept new work
2. should_remove?/1 - checks if worker should be removed
3. update_health/2 - updates health status

Include proper typespec annotations.
```

### Prompt 2.1.4 - Test State Machine
```
Create test/dspex/python_bridge/worker_state_machine_test.exs with comprehensive tests:
1. Valid state transitions for all paths
2. Invalid transition attempts  
3. Health status updates
4. Transition history tracking
5. can_accept_work? in different states

Run the tests and show results.
```

## Session 2.2: Enhanced Worker Implementation

### Prompt 2.2.1 - Create Enhanced Worker Module
```
Create lib/dspex/python_bridge/pool_worker_v2_enhanced.ex from Design Doc 3. Start with:
1. Module attributes and struct definition
2. The behavior declaration
3. Health check constants

This will be our new worker implementation with state machine integration.
```

### Prompt 2.2.2 - Implement init_worker
```
Implement the init_worker callback in PoolWorkerV2Enhanced that:
1. Creates a new WorkerStateMachine
2. Starts the Python process
3. Performs initialization
4. Transitions to ready state on success
5. Raises on failure

Include proper error handling and logging.
```

### Prompt 2.2.3 - Implement handle_checkout
```
Implement handle_checkout in PoolWorkerV2Enhanced that:
1. Checks if worker can accept work via state machine
2. Performs the checkout with state transition
3. Updates session tracking
4. Returns proper NimblePool responses

Focus on the session checkout case first.
```

### Prompt 2.2.4 - Implement handle_checkin
```
Implement handle_checkin with the three cases:
1. Successful checkin - transition back to ready
2. Error checkin - possibly degrade worker
3. Close checkin - remove worker

Include health check scheduling and failure counting.
```

## Session 2.3: Health Monitoring

### Prompt 2.3.1 - Health Check Implementation
```
Add the health monitoring functions to PoolWorkerV2Enhanced:
1. maybe_perform_health_check/1
2. perform_health_check/1  
3. execute_health_check/1
4. handle_health_check_success/2
5. handle_health_check_failure/2

These should integrate with the state machine for state transitions.
```

### Prompt 2.3.2 - Test Health Monitoring
```
Create tests for health monitoring:
1. Successful health checks reset failure count
2. Failed health checks increment counter
3. Max failures trigger worker removal
4. Degraded workers can recover
5. Health check intervals are respected

Add to the enhanced worker test file.
```

## Session 2.4: Session Affinity Manager

### Prompt 2.4.1 - Create Session Affinity Module
```
Create lib/dspex/python_bridge/session_affinity.ex from Design Doc 3. This module should:
1. Use ETS for session-worker mappings
2. Support bind/unbind operations
3. Handle session expiration
4. Clean up worker sessions on removal

Include the GenServer implementation.
```

### Prompt 2.4.2 - Implement Cleanup Logic
```
Add the cleanup functionality to SessionAffinity:
1. Periodic cleanup of expired sessions
2. Remove all sessions for a terminated worker
3. Configurable session timeout
4. Telemetry for session metrics

Test the cleanup logic works correctly.
```

### Prompt 2.4.3 - Integration Test
```
Create an integration test that verifies:
1. Sessions stick to the same worker
2. Expired sessions are cleaned up
3. Worker removal cleans its sessions
4. New sessions distribute across workers

Show the test implementation and results.
```

## Session 2.5: Worker Recovery Strategies

### Prompt 2.5.1 - Create Recovery Module
```
Create lib/dspex/python_bridge/worker_recovery.ex from Design Doc 3. Implement:
1. determine_strategy/3 function
2. Recovery action types
3. Integration with ErrorHandler

This module decides how to handle worker failures.
```

### Prompt 2.5.2 - Implement Recovery Actions
```
Implement the execute_recovery/3 function and its helper functions:
1. degrade_worker/2
2. remove_worker/3  
3. replace_worker/2

Each should integrate with the state machine and session affinity.
```

### Prompt 2.5.3 - Test Recovery Scenarios
```
Create comprehensive tests for recovery:
1. Port exit triggers removal
2. Health check failures trigger degradation
3. Timeout errors trigger retry
4. Non-recoverable errors trigger removal

Verify the state machine transitions are correct.
```

## Session 2.6: Pool Integration

### Prompt 2.6.1 - Update SessionPoolV2
```
Update lib/dspex/python_bridge/session_pool_v2.ex to:
1. Start the SessionAffinity process in init
2. Use session affinity in execute_in_session
3. Handle worker replacement requests
4. Integrate with enhanced workers

Show the key changes needed.
```

### Prompt 2.6.2 - Configure Enhanced Workers
```
Update the pool configuration to use PoolWorkerV2Enhanced:
1. Update supervisor child specs
2. Configure health check intervals
3. Set recovery thresholds
4. Enable session affinity

Test that the pool starts with enhanced workers.
```

## Session 2.7: Metrics Integration

### Prompt 2.7.1 - Add Worker Metrics
```
Create lib/dspex/python_bridge/worker_metrics.ex from Design Doc 3 to track:
1. State transitions with duration
2. Health check results
3. Session affinity hits/misses
4. Recovery actions

Use telemetry for all metrics.
```

### Prompt 2.7.2 - Test Metrics Collection
```
Create tests that verify:
1. All state transitions emit telemetry
2. Health checks are tracked
3. Session affinity is measured
4. Metrics can be queried

Show the implementation and test results.
```

## Session 2.8: Integration Testing

### Prompt 2.8.1 - Worker Lifecycle Test
```
Create test/dspex/python_bridge/worker_lifecycle_integration_test.exs from Design Doc 3. Include:
1. Worker health check recovery test
2. Session affinity maintenance test  
3. State transition verification
4. Concurrent operation handling

Run with TEST_MODE=full_integration.
```

### Prompt 2.8.2 - Stress Testing
```
Create a stress test that:
1. Starts pool with 5 workers
2. Simulates worker failures
3. Verifies recovery and continuity
4. Checks no sessions are lost
5. Validates metrics accuracy

This ensures our lifecycle management is robust.
```

## Session 2.9: Documentation and Validation

### Prompt 2.9.1 - Update Documentation
```
Update the documentation:
1. Add worker state diagram to README
2. Document health check configuration
3. Explain session affinity behavior
4. Create troubleshooting guide

Also update CLAUDE.md with Phase 2 completion status.
```

### Prompt 2.9.2 - Phase 2 Validation
```
Validate Phase 2 completion:
1. Run all new tests
2. Run Phase 1 tests to ensure no regression
3. Verify all Design Doc 3 components implemented
4. Check code coverage
5. Create Phase 2 completion report

Prepare transition to Phase 3.
```

## Session 2.10: Migration Testing

### Prompt 2.10.1 - Test Migration Path
```
Test the migration from basic workers to enhanced workers:
1. Start pool with basic workers
2. Deploy enhanced worker code
3. Perform rolling update
4. Verify no service disruption
5. Confirm metrics continuity

This validates our upgrade path.
```

### Prompt 2.10.2 - Performance Comparison
```
Run performance comparison:
1. Benchmark basic worker pool
2. Benchmark enhanced worker pool
3. Compare latency, throughput, error recovery
4. Document performance improvements
5. Identify any regressions

Create a comparison report.
```