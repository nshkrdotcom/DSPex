# V2 Pool Implementation Prompts - Phase 4: Test Infrastructure Overhaul

## Session 4.1: Test Isolation Framework

### Prompt 4.1.1 - Create Test Isolation Module
```
We're implementing Phase 4 of the V2 Pool design, specifically test infrastructure.
Current status: Phase 3 error handling complete
Today's goal: Create comprehensive test isolation framework

Create test/support/test_isolation.ex from Design Doc 5. Start with:
1. The isolated_test macro
2. Isolated supervisor creation
3. Test environment building
4. Cleanup functionality

Show the core implementation.
```

### Prompt 4.1.2 - Implement Supervision Tree
```
Implement the test supervision tree building:
1. build_supervision_tree/2 for different test layers
2. Layer-specific component selection
3. Unique naming to avoid conflicts
4. Proper startup ordering

Test that isolated supervisors start correctly.
```

### Prompt 4.1.3 - Add Cleanup Logic
```
Implement comprehensive cleanup:
1. cleanup_orphaned_processes/1
2. cleanup_ets_tables/1
3. cleanup_test_files/1
4. Graceful supervisor shutdown

Verify no resources leak between tests.
```

### Prompt 4.1.4 - Test the Framework
```
Create tests for the isolation framework itself:
1. Multiple isolated tests run without conflicts
2. Resources are properly cleaned up
3. Test failures don't affect other tests
4. Different layers work correctly
5. Performance overhead is acceptable

Run tests to verify isolation works.
```

## Session 4.2: Deterministic Test Helpers

### Prompt 4.2.1 - Create Deterministic Helpers
```
Create test/support/deterministic_helpers.ex from Design Doc 5 with:
1. wait_for/3 function for reliable async waiting
2. synchronize/1 for coordinating concurrent ops
3. ensure_pool_ready/3 for pool initialization
4. inject_failure/3 for controlled failures

These ensure predictable test execution.
```

### Prompt 4.2.2 - Implement Failure Injection
```
Implement the failure injection functions:
1. simulate_port_crash/1
2. simulate_timeout/2
3. simulate_network_partition/2
4. simulate_resource_exhaustion/1

Test each injection method works reliably.
```

### Prompt 4.2.3 - Test Synchronization
```
Create tests for the synchronization helpers:
1. Multiple operations start simultaneously
2. Results are collected correctly
3. Timeouts are handled
4. Order is deterministic
5. No race conditions

Verify helpers work under load.
```

## Session 4.3: Enhanced Pool Test Helpers

### Prompt 4.3.1 - Update Pool Test Helpers
```
Update test/support/pool_test_helpers.ex with:
1. start_isolated_pool/1 with full isolation
2. concurrent_pool_operations/2 helper
3. with_pool_monitoring/2 for metrics
4. simulate_pool_failure/3 scenarios

Build on the existing helpers.
```

### Prompt 4.3.2 - Implement Monitoring
```
Add pool monitoring functionality:
1. start_pool_monitor/1 to track events
2. Real-time metrics collection
3. Event aggregation
4. Statistical analysis
5. Performance tracking

Test monitoring doesn't affect pool performance.
```

### Prompt 4.3.3 - Add Chaos Testing
```
Implement chaos testing scenarios:
1. simulate_cascade_failure/2
2. simulate_thundering_herd/2
3. simulate_slow_worker/2
4. simulate_memory_leak/2

These help test resilience.
```

## Session 4.4: Unit Test Updates

### Prompt 4.4.1 - Create Worker State Machine Tests
```
Create comprehensive unit tests using the new framework:
1. Update worker state machine tests
2. Use isolated_test macro
3. Add property-based tests
4. Test all state transitions
5. Verify deterministic behavior

Run and ensure 100% coverage.
```

### Prompt 4.4.2 - Create Error Handler Tests
```
Update error handler tests with isolation:
1. Test each error category
2. Verify recovery strategies
3. Test concurrent error handling
4. Validate error context
5. Check telemetry emission

All tests should be isolated.
```

## Session 4.5: Integration Test Suite

### Prompt 4.5.1 - Create Pool Integration Tests
```
Create test/dspex/python_bridge/pool_integration_test.exs using the new framework:
1. Test concurrent sessions with isolation
2. Worker failure recovery tests
3. Load balancing verification
4. Session affinity tests
5. Error propagation tests

Each test fully isolated.
```

### Prompt 4.5.2 - Multi-Layer Testing
```
Create tests that verify layer compatibility:
1. Layer 1 (mock) isolation
2. Layer 2 (bridge mock) isolation
3. Layer 3 (full integration) isolation
4. Layer transitions
5. Fallback between layers

Test all combinations work.
```

## Session 4.6: Performance Test Suite

### Prompt 4.6.1 - Create Performance Framework
```
Create test/dspex/python_bridge/pool_performance_test.exs from Design Doc 5:
1. Throughput benchmarks
2. Latency distribution tests
3. Resource usage tracking
4. Scalability tests
5. Comparison with baseline

Use the @tag :performance pattern.
```

### Prompt 4.6.2 - Implement Benchmarks
```
Implement specific benchmarks:
1. warmup_pool/2 for consistent starts
2. benchmark_pool_operations/2 
3. measure_latency_distribution/2
4. calculate_percentiles/2
5. Result aggregation

Run benchmarks and establish baselines.
```

### Prompt 4.6.3 - Load Testing
```
Create realistic load tests:
1. Gradual ramp-up to 1000 ops/sec
2. Sustained load for 5 minutes
3. Spike testing
4. Mixed operation types
5. Error injection under load

Verify performance SLAs.
```

## Session 4.7: Chaos Testing

### Prompt 4.7.1 - Create Chaos Test Suite
```
Create test/dspex/python_bridge/pool_chaos_test.exs:
1. Cascading failure scenarios
2. Resource exhaustion tests
3. Network partition simulation
4. Byzantine failures
5. Recovery verification

Use @tag :chaos for these tests.
```

### Prompt 4.7.2 - Implement Chaos Scenarios
```
Implement specific chaos scenarios:
1. Kill 60% of workers rapidly
2. Introduce variable network delays
3. Corrupt random messages
4. Exhaust memory gradually
5. Combine multiple failures

Verify system stability.
```

## Session 4.8: CI/CD Integration

### Prompt 4.8.1 - Test Configuration
```
Update config/test.exs with:
1. Layer-specific configurations
2. Performance thresholds
3. Test isolation settings
4. Timeout configurations
5. Logging levels

Ensure tests run correctly in CI.
```

### Prompt 4.8.2 - Create Test Scripts
```
Create test execution scripts:
1. run_unit_tests.sh for fast feedback
2. run_integration_tests.sh by layer
3. run_performance_tests.sh with reports
4. run_chaos_tests.sh for resilience
5. run_all_tests.sh for complete validation

Include proper error handling.
```

## Session 4.9: Test Documentation

### Prompt 4.9.1 - Testing Guide
```
Create comprehensive testing documentation:
1. Test architecture overview
2. How to write isolated tests
3. Performance testing guide
4. Chaos testing procedures
5. CI/CD test execution

Include examples for each type.
```

### Prompt 4.9.2 - Test Patterns
```
Document test patterns and anti-patterns:
1. Proper test isolation
2. Deterministic test writing
3. Performance test design
4. Common pitfalls
5. Best practices

Create TEST_PATTERNS.md.
```

## Session 4.10: Validation and Migration

### Prompt 4.10.1 - Run Complete Test Suite
```
Execute the complete test suite:
1. Run all unit tests
2. Run integration tests for each layer
3. Run performance tests
4. Run chaos tests
5. Generate coverage report

Fix any failing tests.
```

### Prompt 4.10.2 - Phase 4 Completion
```
Validate Phase 4 completion:
1. All tests using new framework
2. No test interdependencies
3. Deterministic execution
4. Performance baselines established
5. CI/CD integration working

Create completion report and prepare for Phase 5.
```

## Session 4.11: Test Maintenance

### Prompt 4.11.1 - Create Test Utilities
```
Create additional test utilities:
1. Test data generators
2. Assertion helpers
3. Custom test reporters
4. Performance analyzers
5. Failure analyzers

Add to test/support/.
```

### Prompt 4.11.2 - Continuous Improvement
```
Set up continuous test improvement:
1. Flaky test detection
2. Performance regression detection
3. Coverage tracking
4. Test execution time monitoring
5. Automated test updates

Document the process.
```