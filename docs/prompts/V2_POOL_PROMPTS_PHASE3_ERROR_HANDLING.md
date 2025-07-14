# V2 Pool Implementation Prompts - Phase 3: Error Handling and Recovery

## Session 3.1: Pool Error Handler

### Prompt 3.1.1 - Create Pool Error Handler
```
We're implementing Phase 3 of the V2 Pool design, specifically comprehensive error handling.
Current status: Phase 2 worker lifecycle complete
Today's goal: Implement the PoolErrorHandler module

Create lib/dspex/python_bridge/pool_error_handler.ex from Design Doc 4. Start with:
1. Error category type definitions
2. The wrap_pool_error/2 function
3. Error classification logic

Show the initial implementation.
```

### Prompt 3.1.2 - Implement Error Classification
```
Implement the private functions in PoolErrorHandler:
1. categorize_error/1 - maps errors to categories
2. determine_severity/2 - assigns severity levels
3. determine_recovery_strategy/3 - decides recovery approach

Include the retry delay calculations.
```

### Prompt 3.1.3 - Add Retry Logic
```
Implement the retry-related functions:
1. should_retry?/2 - determines if retry is appropriate
2. get_retry_delay/2 - calculates backoff delays
3. format_for_logging/1 - creates detailed error logs

Test with various error scenarios.
```

### Prompt 3.1.4 - Test Error Handler
```
Create test/dspex/python_bridge/pool_error_handler_test.exs with tests for:
1. Error categorization accuracy
2. Severity determination logic
3. Recovery strategy selection
4. Retry delay calculations
5. Error context preservation

Run tests and verify all error types are handled.
```

## Session 3.2: Circuit Breaker Implementation

### Prompt 3.2.1 - Create Circuit Breaker
```
Create lib/dspex/python_bridge/circuit_breaker.ex from Design Doc 4. Implement:
1. GenServer structure and state
2. Circuit states (closed, open, half-open)
3. Configuration with thresholds
4. Basic state management

Focus on the core state machine first.
```

### Prompt 3.2.2 - Implement Circuit Logic
```
Add the core circuit breaker functionality:
1. with_circuit/3 - executes function with circuit protection
2. State transition logic (closed->open->half-open->closed)
3. Failure counting and threshold checking
4. Half-open request limiting

Include telemetry events for monitoring.
```

### Prompt 3.2.3 - Add Circuit Operations
```
Implement the operational functions:
1. record_success/1 and record_failure/2
2. get_state/1 for monitoring
3. reset/1 for manual intervention
4. Timeout handling for half-open transition

Ensure thread safety for concurrent operations.
```

### Prompt 3.2.4 - Test Circuit Breaker
```
Create comprehensive circuit breaker tests:
1. Opens after threshold failures
2. Transitions to half-open after timeout
3. Closes after successful recovery
4. Limits requests in half-open state
5. Handles concurrent operations correctly

Include property-based tests for state transitions.
```

## Session 3.3: Retry Logic Implementation

### Prompt 3.3.1 - Create Retry Module
```
Create lib/dspex/python_bridge/retry_logic.ex from Design Doc 4. Implement:
1. with_retry/2 function signature
2. Backoff strategies (linear, exponential, fibonacci, jitter)
3. Integration with circuit breaker
4. Configurable retry limits

Start with the main retry loop.
```

### Prompt 3.3.2 - Implement Backoff Strategies
```
Implement all backoff calculation strategies:
1. Linear backoff
2. Exponential backoff  
3. Fibonacci sequence
4. Decorrelated jitter (AWS-style)
5. Custom function support

Test each strategy's delay calculations.
```

### Prompt 3.3.3 - Test Retry Logic
```
Create tests for retry logic:
1. Succeeds on retry after failure
2. Respects max attempts
3. Uses correct backoff delays
4. Integrates with circuit breaker
5. Handles different error types

Verify retry telemetry is emitted.
```

## Session 3.4: Error Recovery Orchestrator

### Prompt 3.4.1 - Create Orchestrator
```
Create lib/dspex/python_bridge/error_recovery_orchestrator.ex from Design Doc 4. This coordinates complex recovery:
1. GenServer with recovery state tracking
2. Recovery strategy determination
3. Async recovery execution
4. Metrics tracking

Start with the base structure.
```

### Prompt 3.4.2 - Implement Recovery Strategies
```
Implement the recovery execution logic:
1. determine_recovery_strategy/2
2. execute_recovery/2 with different strategies
3. Retry with backoff
4. Failover to alternate adapter
5. Circuit breaking

Include timeout handling for recovery operations.
```

### Prompt 3.4.3 - Add Recovery Actions
```
Implement specific recovery actions:
1. attempt_recovery/1 for different error types
2. attempt_failover/2 to alternate adapter
3. Resource cleanup and retry
4. Recovery result handling

Test each recovery path.
```

### Prompt 3.4.4 - Integration Testing
```
Create integration tests for the orchestrator:
1. Handles connection errors with retry
2. Fails over when primary adapter fails
3. Respects circuit breaker state
4. Tracks recovery metrics
5. Handles cascading failures

Run with different error scenarios.
```

## Session 3.5: Pool Integration

### Prompt 3.5.1 - Update SessionPoolV2
```
Update lib/dspex/python_bridge/session_pool_v2.ex to use error handling:
1. Wrap operations in RetryLogic.with_retry
2. Use PoolErrorHandler for all errors
3. Integrate CircuitBreaker for protection
4. Add recovery orchestration

Show the key integration points.
```

### Prompt 3.5.2 - Error Context Enhancement
```
Enhance error context throughout pool operations:
1. Add operation metadata to errors
2. Include timing information
3. Track retry attempts
4. Add session and worker details

This enables better debugging and monitoring.
```

### Prompt 3.5.3 - Test Error Scenarios
```
Create test scenarios for common errors:
1. Worker crash during operation
2. Timeout during checkout
3. Python process unresponsive
4. Resource exhaustion
5. Network issues

Verify proper error handling and recovery.
```

## Session 3.6: Error Reporting

### Prompt 3.6.1 - Create Error Reporter
```
Create lib/dspex/python_bridge/error_reporter.ex from Design Doc 4 for centralized reporting:
1. Telemetry event handling
2. Error aggregation
3. Alert triggering
4. Integration points for monitoring

This provides visibility into errors.
```

### Prompt 3.6.2 - Configure Telemetry
```
Set up comprehensive telemetry:
1. Attach handlers for error events
2. Configure error severity levels
3. Set up alert thresholds
4. Create error dashboards

Test that all errors are captured.
```

## Session 3.7: Fallback Strategies

### Prompt 3.7.1 - Implement Adapter Fallback
```
Implement fallback logic for adapter failures:
1. Primary -> Secondary adapter fallback
2. Pool -> Single bridge fallback
3. Python -> Mock adapter fallback
4. Graceful degradation

Test fallback transitions.
```

### Prompt 3.7.2 - Test Fallback Scenarios
```
Create comprehensive fallback tests:
1. Automatic fallback on primary failure
2. Fallback with data consistency
3. Recovery to primary when available
4. Multiple fallback levels
5. Performance during fallback

Verify no data loss during transitions.
```

## Session 3.8: Performance Testing

### Prompt 3.8.1 - Error Handling Performance
```
Create performance tests for error handling:
1. Measure retry overhead
2. Circuit breaker performance impact
3. Error handling latency
4. Recovery time benchmarks
5. Throughput during failures

Compare with baseline performance.
```

### Prompt 3.8.2 - Load Testing with Failures
```
Run load tests with injected failures:
1. 1000 ops/sec with 5% failures
2. Cascading worker failures
3. Intermittent timeout errors
4. Circuit breaker activations
5. Recovery under load

Verify SLAs are maintained.
```

## Session 3.9: Documentation

### Prompt 3.9.1 - Error Handling Guide
```
Create comprehensive error handling documentation:
1. Error categories and meanings
2. Recovery strategies for each type
3. Configuration options
4. Monitoring and alerts
5. Troubleshooting guide

Include flow diagrams for error paths.
```

### Prompt 3.9.2 - Runbook Creation
```
Create operational runbooks for:
1. Circuit breaker opened
2. High error rate alerts
3. Worker failure patterns
4. Recovery procedures
5. Manual interventions

These guide operations teams.
```

## Session 3.10: Phase Validation

### Prompt 3.10.1 - Error Injection Testing
```
Run comprehensive error injection tests:
1. Kill Python processes randomly
2. Introduce network delays
3. Exhaust resources
4. Corrupt messages
5. Simulate partial failures

Verify system remains stable.
```

### Prompt 3.10.2 - Phase 3 Completion
```
Validate Phase 3 completion:
1. All error paths tested
2. Recovery strategies verified
3. Performance impact acceptable
4. Documentation complete
5. No regressions from Phase 1-2

Create completion report and prepare for Phase 4.
```