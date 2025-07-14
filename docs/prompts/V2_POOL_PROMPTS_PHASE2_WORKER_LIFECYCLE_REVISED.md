# V2 Pool Implementation Prompts - Phase 2: Worker Lifecycle Management (REVISED)

## Session 2.1: Worker State Machine Implementation

### Prompt 2.1.1 - Create State Machine Module
```
We're implementing Phase 2 of the V2 Pool design, specifically the Worker State Machine.

First, read these files to understand the requirements:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md section "Worker State Machine"
2. Read docs/V2_POOL_TECHNICAL_DESIGN_1_OVERVIEW.md section "Design Principles" 
3. Check if the file exists: ls lib/dspex/python_bridge/worker_state_machine.ex

Now create lib/dspex/python_bridge/worker_state_machine.ex with:
1. Module declaration and moduledoc
2. Type definitions for state, health, and transition reasons
3. The main struct with all fields
4. The new/1 function to create instances

Show me:
1. The complete type definitions
2. The struct definition
3. The new/1 function implementation
```

### Prompt 2.1.2 - Implement State Transitions
```
Let's implement the state transition logic.

First, re-read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md section "State Transition Diagram"
2. The @valid_transitions map shown in the design
3. Your current worker_state_machine.ex file

Now implement:
1. The @valid_transitions map constant
2. The transition/4 public function that validates transitions
3. The do_transition/4 private function that performs transitions
4. Include proper logging and history tracking

Show me:
1. The @valid_transitions definition
2. The complete transition/4 function
3. The complete do_transition/4 function
4. Example of how transition history is recorded
```

### Prompt 2.1.3 - Add Helper Functions
```
Let's add the helper functions for state queries.

First, review:
1. The current worker_state_machine.ex implementation
2. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md for helper function specs

Add these helper functions:
1. can_accept_work?/1 - returns true only if state is :ready and health is :healthy
2. should_remove?/1 - returns true if state is :terminating or :terminated  
3. update_health/2 - updates the health status field

Include:
- Proper @doc strings
- @spec type specifications
- Pattern matching for efficiency

Show me the complete implementation of all three functions.
```

### Prompt 2.1.4 - Test State Machine
```
Let's create comprehensive tests for the state machine.

First, check test directory:
1. Run: ls test/dspex/python_bridge/
2. If it doesn't exist: mkdir -p test/dspex/python_bridge/

Create test/dspex/python_bridge/worker_state_machine_test.exs with:
1. Module setup with ExUnit.Case
2. Test valid transitions for all allowed paths
3. Test invalid transition rejection
4. Test health status updates
5. Test transition history tracking
6. Test helper functions (can_accept_work?, should_remove?)

After creating:
1. Run: mix test test/dspex/python_bridge/worker_state_machine_test.exs
2. Show me the complete test file
3. Show me test results
```

## Session 2.2: Enhanced Worker Implementation

### Prompt 2.2.1 - Create Enhanced Worker Module
```
Let's create the enhanced worker with state machine integration.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md section "Enhanced Worker Module"
2. Current lib/dspex/python_bridge/pool_worker_v2.ex to understand base implementation
3. Check: ls lib/dspex/python_bridge/pool_worker_v2_enhanced.ex

Create lib/dspex/python_bridge/pool_worker_v2_enhanced.ex with:
1. Module declaration with @behaviour NimblePool
2. Alias for WorkerStateMachine
3. defstruct with all fields from design
4. Module attributes for health check constants

Show me:
1. The complete module header with aliases
2. The defstruct definition
3. The constant definitions
```

### Prompt 2.2.2 - Implement init_worker
```
Let's implement the worker initialization with state machine.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md section showing init_worker
2. Current pool_worker_v2.ex init_worker for reference
3. The start_python_process and perform_initialization functions

Implement init_worker/1 that:
1. Generates unique worker_id
2. Creates new WorkerStateMachine
3. Starts Python process
4. Performs initialization
5. Transitions to ready state on success
6. Raises on failure with proper cleanup

Show me:
1. The complete init_worker implementation
2. How it integrates with the state machine
3. Error handling approach
```

### Prompt 2.2.3 - Implement handle_checkout
```
Let's implement checkout with state validation.

First, read:
1. The WorkerStateMachine.can_accept_work? function we created
2. Current handle_checkout in pool_worker_v2.ex
3. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md checkout section

Implement handle_checkout/4 that:
1. First checks if worker can accept work
2. Performs state transition to :busy
3. Handles session tracking
4. Returns proper NimblePool responses
5. Removes worker if not ready

Show me:
1. The complete handle_checkout implementation
2. How it handles both session and anonymous checkouts
3. State machine integration points
```

### Prompt 2.2.4 - Implement handle_checkin
```
Let's implement the checkin logic with health monitoring.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md handle_checkin section
2. The three checkin types: :ok, :error, :close
3. Health check and failure counting logic

Implement handle_checkin/4 with:
1. maybe_perform_health_check/1 call
2. Different handling for each checkin type
3. State transitions back to ready or degraded
4. Failure counting and threshold checks
5. Worker removal on max failures

Show me:
1. The complete handle_checkin implementation
2. Each checkin type handler
3. How health check scheduling works
```

## Session 2.3: Health Monitoring

### Prompt 2.3.1 - Health Check Implementation
```
Let's implement the health monitoring system.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md section "Health monitoring"
2. Review the health check constants we defined
3. Current Python bridge health check command format

Implement these health check functions:
1. maybe_perform_health_check/1 - checks if due
2. perform_health_check/1 - orchestrates the check
3. execute_health_check/1 - sends command to Python
4. handle_health_check_success/2 - processes success
5. handle_health_check_failure/2 - processes failure

Show me:
1. All five functions with complete implementation
2. How they integrate with state machine
3. Timeout handling approach
```

### Prompt 2.3.2 - Test Health Monitoring
```
Let's test the health monitoring system.

First, check existing test file or create new:
1. Run: ls test/dspex/python_bridge/pool_worker_v2_enhanced_test.exs
2. If missing, create it

Add health monitoring tests:
1. Test successful health checks reset failure count
2. Test failed health checks increment counter
3. Test max failures trigger worker removal
4. Test degraded workers can recover to ready
5. Test health check interval is respected
6. Mock the Python port for deterministic testing

After implementing:
1. Run: mix test test/dspex/python_bridge/pool_worker_v2_enhanced_test.exs
2. Show me the test implementation
3. Show me test results
```

## Session 2.4: Session Affinity Manager

### Prompt 2.4.1 - Create Session Affinity Module
```
Let's create the session affinity manager.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md section "Session Affinity Manager"
2. Understand ETS table usage for performance
3. Check: ls lib/dspex/python_bridge/session_affinity.ex

Create lib/dspex/python_bridge/session_affinity.ex with:
1. GenServer setup and start_link
2. ETS table creation in init
3. bind_session/2 function
4. get_worker/1 function  
5. unbind_session/1 function
6. remove_worker_sessions/1 function

Show me:
1. The complete GenServer setup
2. ETS table configuration
3. All public API functions
```

### Prompt 2.4.2 - Implement Cleanup Logic
```
Let's add session cleanup functionality.

First, review:
1. Your current session_affinity.ex implementation
2. The cleanup requirements from design doc
3. ETS select patterns for efficient cleanup

Add to SessionAffinity:
1. Periodic cleanup scheduling in init
2. handle_info(:cleanup, state) implementation
3. cleanup_expired_sessions/0 private function
4. Configurable session timeout
5. Logging of cleanup operations

Show me:
1. The updated init function with scheduling
2. Complete cleanup implementation
3. How expired sessions are detected
```

### Prompt 2.4.3 - Integration Test
```
Let's test session affinity with pool operations.

Create test/dspex/python_bridge/session_affinity_test.exs with:
1. Test session-worker binding persistence
2. Test expired session cleanup
3. Test worker removal cleans its sessions
4. Test concurrent session operations
5. Test get_worker returns correct worker

Also create integration test:
1. Multiple sessions stick to same worker
2. New sessions distribute across workers
3. Performance of lookup operations

Run tests:
1. mix test test/dspex/python_bridge/session_affinity_test.exs
2. Show me test file and results
```

## Session 2.5: Worker Recovery Strategies

### Prompt 2.5.1 - Create Recovery Module
```
Let's implement worker recovery strategies.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md section "Worker Recovery Strategies"
2. Review the recovery decision tree
3. Check: ls lib/dspex/python_bridge/worker_recovery.ex

Create lib/dspex/python_bridge/worker_recovery.ex with:
1. Type definitions for recovery actions
2. determine_strategy/3 main decision function
3. Integration with ErrorHandler module
4. Recovery action type definitions

Show me:
1. The module structure and types
2. The determine_strategy implementation
3. How it integrates with ErrorHandler
```

### Prompt 2.5.2 - Implement Recovery Actions
```
Let's implement the recovery execution functions.

First, review:
1. Your current worker_recovery.ex file
2. The recovery strategies from design
3. How WorkerStateMachine transitions work

Implement in worker_recovery.ex:
1. execute_recovery/3 that dispatches to actions
2. degrade_worker/2 private function
3. remove_worker/3 private function
4. replace_worker/2 private function
5. Proper logging for each action

Show me:
1. The complete execute_recovery function
2. All recovery action implementations
3. How they update worker state
```

### Prompt 2.5.3 - Test Recovery Scenarios
```
Let's test the recovery strategies.

Create test/dspex/python_bridge/worker_recovery_test.exs with:
1. Test port exit triggers removal
2. Test health failures trigger degradation  
3. Test timeout errors trigger retry
4. Test non-recoverable errors trigger removal
5. Test recovery strategy selection logic

Mock scenarios:
1. Create mock worker states
2. Simulate various failure types
3. Verify correct strategies chosen
4. Check state transitions

Run tests and show results.
```

## Session 2.6: Pool Integration

### Prompt 2.6.1 - Update SessionPoolV2
```
Let's integrate enhanced workers with the pool.

First, read:
1. Current lib/dspex/python_bridge/session_pool_v2.ex
2. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md pool integration section
3. How SessionAffinity should be started

Update session_pool_v2.ex to:
1. Start SessionAffinity in init/1
2. Use affinity in execute_in_session
3. Handle worker replacement messages
4. Configure to use enhanced workers

Show me:
1. The updated init function
2. Updated execute_in_session with affinity
3. New handle_info for replacements
```

### Prompt 2.6.2 - Configure Enhanced Workers
```
Let's configure the pool to use enhanced workers.

First, check:
1. Current pool configuration approach
2. Where worker module is specified
3. Config files: ls config/

Update configuration:
1. Set worker module to PoolWorkerV2Enhanced
2. Configure health check intervals
3. Set failure thresholds
4. Enable session affinity
5. Update supervisor specs if needed

Show me:
1. Configuration changes needed
2. How to verify enhanced workers are used
3. Test that pool starts correctly
```

## Session 2.7: Metrics Integration

### Prompt 2.7.1 - Add Worker Metrics
```
Let's add comprehensive worker metrics.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md metrics section
2. Check existing telemetry usage: grep -r "telemetry" lib/
3. Check: ls lib/dspex/python_bridge/worker_metrics.ex

Create lib/dspex/python_bridge/worker_metrics.ex with:
1. Telemetry event definitions
2. record_transition/4 for state changes
3. record_health_check/3 for health results
4. record_session_affinity/3 for cache hits
5. Consistent event metadata

Show me:
1. Complete metrics module
2. Event naming conventions
3. Metadata structure
```

### Prompt 2.7.2 - Test Metrics Collection
```
Let's verify metrics are emitted correctly.

Create test/dspex/python_bridge/worker_metrics_test.exs:
1. Set up telemetry handler in test
2. Test state transitions emit events
3. Test health checks are tracked
4. Test session affinity metrics
5. Verify event metadata

Use telemetry test helpers:
1. Capture events during operations
2. Assert on event names and measurements
3. Verify metadata completeness

Run tests and show implementation.
```

## Session 2.8: Integration Testing

### Prompt 2.8.1 - Worker Lifecycle Test
```
Let's create comprehensive integration tests.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_3_WORKER_LIFECYCLE.md integration test section
2. Test helpers available: ls test/support/

Create test/dspex/python_bridge/worker_lifecycle_integration_test.exs:
1. Set up with @moduletag :integration
2. Test worker health check recovery
3. Test session affinity maintenance
4. Test state transitions during operations
5. Test concurrent operations

Ensure TEST_MODE=full_integration is used.

Show me:
1. Complete test file
2. How to run: TEST_MODE=full_integration mix test [file]
3. Test results
```

### Prompt 2.8.2 - Stress Testing
```
Let's stress test the lifecycle management.

Add stress tests to integration file:
1. Start pool with 5 workers
2. Simulate random worker failures
3. Verify recovery and continuity
4. Check no sessions are lost
5. Validate metrics accuracy
6. Run for extended duration

Implement helpers:
1. Random failure injection
2. Session tracking
3. Metrics collection
4. Result analysis

Show me:
1. Stress test implementation
2. Results including performance metrics
3. Any issues discovered
```

## Session 2.9: Documentation and Validation

### Prompt 2.9.1 - Update Documentation
```
Let's document the worker lifecycle system.

First, read current docs:
1. README.md to see what exists
2. CLAUDE.md for progress tracking

Update documentation:
1. Add state diagram to README (ASCII or mermaid)
2. Document health check configuration options
3. Explain session affinity behavior
4. Create troubleshooting guide for common issues
5. Update CLAUDE.md with Phase 2 progress

Show me:
1. State diagram in mermaid format
2. Configuration documentation
3. CLAUDE.md updates
```

### Prompt 2.9.2 - Phase 2 Validation
```
Let's validate Phase 2 completion.

Run validation checks:
1. Run all new tests: mix test test/dspex/python_bridge/
2. Run Phase 1 tests to check regression
3. Check code coverage if available
4. Verify all design components implemented
5. Review any TODO comments: grep -r "TODO"

Create Phase 2 completion report:
- Components implemented
- Test coverage
- Performance metrics  
- Known issues
- Ready for Phase 3?

Show me the validation results and report.
```

## Session 2.10: Migration Testing

### Prompt 2.10.1 - Test Migration Path
```
Let's test upgrading from basic to enhanced workers.

Create migration test scenario:
1. Start pool with basic workers (if possible)
2. Deploy enhanced worker code
3. Perform rolling update simulation
4. Verify no service disruption
5. Confirm metrics continuity

Document:
1. Migration steps
2. Any compatibility issues
3. Rollback procedures
4. Performance impact

Show me test results and findings.
```

### Prompt 2.10.2 - Performance Comparison
```
Let's compare basic vs enhanced worker performance.

Create benchmark comparison:
1. Set up basic worker pool (baseline)
2. Set up enhanced worker pool
3. Run same workload on both
4. Measure latency, throughput, recovery time
5. Compare resource usage

Metrics to capture:
- Operation latency (p50, p95, p99)
- Throughput (ops/sec)
- Error recovery time
- Memory usage
- CPU usage

Show me:
1. Benchmark implementation
2. Results comparison table
3. Performance improvement summary
```