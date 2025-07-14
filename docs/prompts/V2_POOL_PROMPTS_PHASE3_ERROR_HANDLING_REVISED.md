# V2 Pool Implementation Prompts - Phase 3: Error Handling and Recovery (REVISED)

## Session 3.1: Pool Error Handler

### Prompt 3.1.1 - Create Pool Error Handler
```
We're implementing Phase 3 of the V2 Pool design, specifically comprehensive error handling.

First, read these files to understand requirements:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md section "Error Classification and Hierarchy"
2. Read lib/dspex/adapters/error_handler.ex to understand existing error handling
3. Check if exists: ls lib/dspex/python_bridge/pool_error_handler.ex

Create lib/dspex/python_bridge/pool_error_handler.ex with:
1. Module declaration and moduledoc
2. Error category type definitions
3. Error context type definition
4. The wrap_pool_error/2 main function
5. Retry delay configuration map

Show me:
1. Complete type definitions
2. The @retry_delays configuration
3. Initial wrap_pool_error implementation
```

### Prompt 3.1.2 - Implement Error Classification
```
Let's implement the error classification logic.

First, re-read:
1. docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md "Error Decision Matrix" table
2. Your current pool_error_handler.ex file
3. The error types we need to handle

Implement these private functions:
1. categorize_error/1 - maps error tuples to categories
2. determine_severity/2 - assigns severity based on category and context
3. determine_recovery_strategy/3 - decides recovery approach
4. upgrade_severity/1 helper function

Show me:
1. Complete categorize_error with all error patterns
2. Severity determination logic with context consideration
3. Recovery strategy selection
```

### Prompt 3.1.3 - Add Retry Logic
```
Let's implement retry decision functions.

First, review:
1. The @retry_delays map you defined
2. docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md retry strategies
3. How ErrorHandler.should_retry? works

Implement:
1. should_retry?/2 that considers strategy and attempt count
2. get_retry_delay/2 that returns appropriate delay
3. format_for_logging/1 for detailed error logs
4. Integration with base ErrorHandler

Show me:
1. Complete should_retry? implementation
2. Retry delay calculation with all strategies
3. Formatted logging output example
```

### Prompt 3.1.4 - Test Error Handler
```
Let's test the pool error handler.

First, check test directory:
1. Run: ls test/dspex/python_bridge/
2. Create if needed: mkdir -p test/dspex/python_bridge/

Create test/dspex/python_bridge/pool_error_handler_test.exs with:
1. Test error categorization for all error types
2. Test severity determination with various contexts
3. Test recovery strategy selection
4. Test retry delays for each strategy
5. Test error context preservation
6. Test logging format

Run tests:
1. mix test test/dspex/python_bridge/pool_error_handler_test.exs
2. Show me complete test file
3. Show test results
```

## Session 3.2: Circuit Breaker Implementation

### Prompt 3.2.1 - Create Circuit Breaker
```
Let's implement the circuit breaker pattern.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md section "Circuit Breaker Implementation"
2. Understand the three states: closed, open, half-open
3. Check: ls lib/dspex/python_bridge/circuit_breaker.ex

Create lib/dspex/python_bridge/circuit_breaker.ex with:
1. GenServer setup with use GenServer
2. Type definitions for states and circuit record
3. Default configuration map
4. start_link and init functions
5. State storage structure

Show me:
1. Complete type definitions
2. Default configuration values
3. GenServer initialization
```

### Prompt 3.2.2 - Implement Circuit Logic
```
Let's implement core circuit breaker functionality.

First, review:
1. Your current circuit_breaker.ex structure
2. State transition rules from design doc
3. How timeouts trigger state changes

Implement:
1. with_circuit/3 main execution function
2. State checking logic (closed/open/half-open)
3. execute_and_track/3 for operation execution
4. Transition decision logic
5. Telemetry event emission

Show me:
1. Complete with_circuit implementation
2. How each state is handled
3. State transition logic
```

### Prompt 3.2.3 - Add Circuit Operations
```
Let's add circuit breaker operations.

First, understand requirements:
1. Success/failure recording
2. State querying
3. Manual reset capability
4. Statistics tracking

Implement these functions:
1. record_success/1 - updates success count
2. record_failure/2 - updates failure count
3. get_state/1 - returns current state
4. reset/1 - manually resets circuit
5. Helper functions for state transitions

Show me:
1. All public API functions
2. State update logic
3. How manual reset works
```

### Prompt 3.2.4 - Test Circuit Breaker
```
Let's comprehensively test the circuit breaker.

Create test/dspex/python_bridge/circuit_breaker_test.exs with:
1. Test opens after threshold failures
2. Test transitions to half-open after timeout
3. Test closes after successful recovery
4. Test half-open request limiting
5. Test concurrent operations
6. Test manual reset

Include:
1. Helper to simulate time passing
2. Concurrent operation tests
3. State transition verification

Run tests and show results.
```

## Session 3.3: Retry Logic Implementation

### Prompt 3.3.1 - Create Retry Module
```
Let's implement sophisticated retry logic.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md section "Retry Logic Implementation"
2. Review backoff strategies needed
3. Check: ls lib/dspex/python_bridge/retry_logic.ex

Create lib/dspex/python_bridge/retry_logic.ex with:
1. Module setup and type definitions
2. with_retry/2 main function signature
3. Backoff strategy types
4. Configuration options structure

Show me:
1. Type definitions for strategies
2. Module structure
3. Main function signature
```

### Prompt 3.3.2 - Implement Backoff Strategies
```
Let's implement all backoff calculation strategies.

First, review:
1. Each strategy's mathematical formula
2. AWS decorrelated jitter approach
3. Max delay limits

Implement:
1. calculate_delay/4 main dispatcher
2. Linear backoff calculation
3. Exponential backoff with base
4. Fibonacci sequence generation
5. Decorrelated jitter with process dictionary
6. Custom function support

Show me:
1. All strategy implementations
2. How delays are capped
3. Example delay sequences
```

### Prompt 3.3.3 - Test Retry Logic
```
Let's test the retry mechanisms.

Create test/dspex/python_bridge/retry_logic_test.exs:
1. Test successful retry after failures
2. Test respects max attempts
3. Test each backoff strategy
4. Test circuit breaker integration
5. Test different error types
6. Test telemetry emission

Include timing tests:
1. Verify delays are applied
2. Check delay calculations
3. Test max delay capping

Show me test implementation and results.
```

## Session 3.4: Error Recovery Orchestrator

### Prompt 3.4.1 - Create Orchestrator
```
Let's create the error recovery orchestrator.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md section "Error Recovery Orchestrator"
2. Understand async recovery execution
3. Check: ls lib/dspex/python_bridge/error_recovery_orchestrator.ex

Create lib/dspex/python_bridge/error_recovery_orchestrator.ex with:
1. GenServer structure
2. State for tracking active recoveries
3. Recovery strategy configuration
4. Metrics tracking structure

Show me:
1. GenServer setup
2. State structure definition
3. How recovery IDs are generated
```

### Prompt 3.4.2 - Implement Recovery Strategies
```
Let's implement recovery execution logic.

First, review:
1. Your orchestrator structure
2. Different recovery strategies from design
3. How to track async operations

Implement:
1. handle_error/2 main entry point
2. determine_recovery_strategy/2
3. execute_recovery/2 with async Task
4. Recovery completion handling
5. Metrics updates

Show me:
1. Complete handle_error implementation
2. Strategy determination logic
3. Async execution approach
```

### Prompt 3.4.3 - Add Recovery Actions
```
Let's implement specific recovery actions.

First, understand:
1. Each recovery action type
2. Integration with pool operations
3. Fallback adapter selection

Implement:
1. attempt_recovery/1 for different errors
2. attempt_failover/2 to alternate adapter
3. Connection recovery logic
4. Resource cleanup approach
5. Result handling

Show me:
1. All recovery action implementations
2. Fallback logic
3. Success/failure handling
```

### Prompt 3.4.4 - Integration Testing
```
Let's test the orchestrator with real scenarios.

Create integration tests:
1. Test connection error recovery
2. Test failover to mock adapter
3. Test circuit breaker interaction
4. Test concurrent recovery operations
5. Test metrics tracking

Set up test scenarios:
1. Mock failing operations
2. Configure fallback adapters
3. Verify recovery execution
4. Check metric updates

Show me test implementation and results.
```

## Session 3.5: Pool Integration

### Prompt 3.5.1 - Update SessionPoolV2
```
Let's integrate error handling into the pool.

First, read:
1. Current lib/dspex/python_bridge/session_pool_v2.ex
2. docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md pool integration
3. How RetryLogic and CircuitBreaker should be used

Update session_pool_v2.ex:
1. Add aliases for error handling modules
2. Wrap execute_in_session with RetryLogic
3. Add PoolErrorHandler for all errors
4. Integrate CircuitBreaker for protection
5. Add recovery orchestration

Show me:
1. Updated module aliases
2. New execute_in_session implementation
3. Error wrapping approach
```

### Prompt 3.5.2 - Error Context Enhancement
```
Let's enhance error context throughout pool.

First, identify:
1. All error points in pool operations
2. What context would be helpful
3. Existing metadata

Enhance error context:
1. Add operation type to all errors
2. Include session_id and worker_id
3. Add timing information
4. Track retry attempt number
5. Include queue depth at error time

Show me:
1. Context structure
2. Where context is added
3. Example enhanced error
```

### Prompt 3.5.3 - Test Error Scenarios
```
Let's test common error scenarios.

Create comprehensive error tests:
1. Worker crash during operation
2. Timeout during checkout
3. Python process becoming unresponsive
4. Pool resource exhaustion
5. Network communication errors

For each scenario:
1. Set up failure condition
2. Execute pool operation
3. Verify error handling
4. Check recovery executed
5. Validate final state

Show me test scenarios and results.
```

## Session 3.6: Error Reporting

### Prompt 3.6.1 - Create Error Reporter
```
Let's create centralized error reporting.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_4_ERROR_HANDLING.md error reporting section
2. Check telemetry patterns: grep -r ":telemetry.attach" lib/
3. Check: ls lib/dspex/python_bridge/error_reporter.ex

Create lib/dspex/python_bridge/error_reporter.ex:
1. GenServer for event handling
2. Telemetry event subscriptions
3. Error aggregation logic
4. Alert triggering thresholds
5. Integration points

Show me:
1. Complete module structure
2. Event subscription setup
3. How alerts are triggered
```

### Prompt 3.6.2 - Configure Telemetry
```
Let's set up comprehensive error telemetry.

First, understand:
1. What events to subscribe to
2. Alert threshold configuration
3. Logging requirements

Configure:
1. Attach handlers for all error events
2. Set severity-based thresholds
3. Configure alert destinations
4. Create error categories
5. Set up aggregation windows

Show me:
1. Handler attachment code
2. Threshold configuration
3. Alert routing logic
```

## Session 3.7: Fallback Strategies

### Prompt 3.7.1 - Implement Adapter Fallback
```
Let's implement fallback between adapters.

First, read:
1. Current adapter structure: ls lib/dspex/adapters/
2. How Factory.execute_with_adapter works
3. Fallback order from design doc

Implement fallback logic:
1. Primary to secondary adapter
2. Pool to single bridge fallback
3. Python to mock adapter fallback
4. Graceful degradation flow
5. Fallback decision logic

Show me:
1. Fallback chain definition
2. Implementation approach
3. How state is preserved
```

### Prompt 3.7.2 - Test Fallback Scenarios
```
Let's test fallback mechanisms.

Create fallback tests:
1. Primary adapter failure triggers fallback
2. Data consistency during fallback
3. Recovery to primary when available
4. Multiple fallback levels
5. Performance during fallback

Test scenarios:
1. Kill primary adapter
2. Verify fallback activates
3. Execute operations on fallback
4. Restore primary
5. Verify switchback

Show me tests and results.
```

## Session 3.8: Performance Testing

### Prompt 3.8.1 - Error Handling Performance
```
Let's measure error handling overhead.

Create performance benchmarks:
1. Baseline operation performance
2. Performance with retry logic
3. Circuit breaker overhead
4. Error wrapping cost
5. Recovery orchestration impact

Use Benchee for measurements:
1. Set up benchmark scenarios
2. Run with various error rates
3. Measure latency impact
4. Check memory overhead

Show me benchmark implementation and results.
```

### Prompt 3.8.2 - Load Testing with Failures
```
Let's test under load with failures.

Create load test with error injection:
1. 1000 ops/sec baseline
2. Inject 5% random failures
3. Add cascading failures
4. Include timeout errors
5. Trigger circuit breakers

Measure:
1. Throughput degradation
2. Recovery time
3. Error rate trends
4. Resource usage
5. SLA compliance

Show me load test setup and results.
```

## Session 3.9: Documentation

### Prompt 3.9.1 - Error Handling Guide
```
Let's create error handling documentation.

First, review what to document:
1. All error categories
2. Recovery strategies
3. Configuration options
4. Monitoring setup

Create comprehensive guide covering:
1. Error category explanations
2. Recovery strategy for each type
3. Configuration reference
4. Monitoring and alerts setup
5. Troubleshooting common issues
6. Flow diagrams for error paths

Show me:
1. Documentation outline
2. Key sections
3. Example configurations
```

### Prompt 3.9.2 - Runbook Creation
```
Let's create operational runbooks.

Create runbooks for:
1. Circuit breaker opened alert
2. High error rate investigation
3. Worker failure patterns
4. Recovery procedure steps
5. Manual intervention guides

Each runbook should have:
1. Alert description
2. Impact assessment
3. Investigation steps
4. Resolution procedures
5. Escalation criteria

Show me example runbook.
```

## Session 3.10: Phase Validation

### Prompt 3.10.1 - Error Injection Testing
```
Let's run comprehensive error injection tests.

Set up chaos testing:
1. Random Python process kills
2. Network delay injection
3. Resource exhaustion simulation
4. Message corruption
5. Partial failure scenarios

For each test:
1. Define failure injection
2. Run for 5 minutes
3. Monitor system behavior
4. Verify recovery
5. Check data integrity

Show me test results and system stability metrics.
```

### Prompt 3.10.2 - Phase 3 Completion
```
Let's validate Phase 3 completion.

Run validation checks:
1. All error paths tested: mix test test/dspex/python_bridge/ --tag error_handling
2. Recovery strategies verified
3. Performance impact measured
4. Documentation complete
5. No regressions from Phase 1-2

Create completion report:
1. Components implemented
2. Test coverage for errors
3. Performance impact summary
4. Known limitations
5. Ready for Phase 4?

Show me validation results and report.
```