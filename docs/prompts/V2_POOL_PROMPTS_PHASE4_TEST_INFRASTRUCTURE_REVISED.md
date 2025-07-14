# V2 Pool Implementation Prompts - Phase 4: Test Infrastructure Overhaul (REVISED)

## Session 4.1: Test Isolation Framework

### Prompt 4.1.1 - Create Test Isolation Module
```
We're implementing Phase 4 of the V2 Pool design, specifically test infrastructure.

First, read these files to understand requirements:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_5_TEST_INFRASTRUCTURE.md section "Test Isolation Framework"
2. Check existing test helpers: ls test/support/
3. Review ExUnit documentation for macros

Create test/support/test_isolation.ex with:
1. Module declaration with proper imports
2. The isolated_test macro definition
3. start_isolated_supervisor/2 function
4. build_test_env/2 function
5. cleanup_test_environment/2 function

Show me:
1. The complete macro implementation
2. How it integrates with ExUnit
3. Initial helper function signatures
```

### Prompt 4.1.2 - Implement Supervision Tree
```
Let's implement isolated supervision trees.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_5_TEST_INFRASTRUCTURE.md supervision tree section
2. Current supervisor structure: ls lib/dspex/python_bridge/*supervisor*
3. How different test layers need different components

Implement in test_isolation.ex:
1. build_supervision_tree/2 with layer-specific logic
2. Base children (Registry, ErrorOrchestrator, CircuitBreaker)
3. Layer-specific children (mock, bridge, full)
4. Unique naming to prevent conflicts
5. Proper startup ordering

Show me:
1. Complete build_supervision_tree implementation
2. How each layer differs
3. Child specifications
```

### Prompt 4.1.3 - Add Cleanup Logic
```
Let's implement comprehensive test cleanup.

First, understand cleanup requirements:
1. Process termination needs
2. ETS table cleanup
3. File system cleanup
4. Registry cleanup

Implement cleanup functions:
1. cleanup_orphaned_processes/1 - find and kill test processes
2. cleanup_ets_tables/1 - remove test ETS tables
3. cleanup_test_files/1 - remove temp files
4. Main cleanup orchestration

Show me:
1. All cleanup function implementations
2. How they find test-specific resources
3. Error handling for cleanup
```

### Prompt 4.1.4 - Test the Framework
```
Let's test the isolation framework itself.

Create test/support/test_isolation_test.exs:
1. Test multiple isolated tests don't conflict
2. Test resources are cleaned up properly
3. Test supervisor isolation works
4. Test different layers work correctly
5. Test cleanup after failures

Include tests for:
1. Process isolation
2. ETS isolation
3. Registry isolation
4. File cleanup

Run tests and show results.
```

## Session 4.2: Deterministic Test Helpers

### Prompt 4.2.1 - Create Deterministic Helpers
```
Let's create helpers for predictable test execution.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_5_TEST_INFRASTRUCTURE.md deterministic helpers section
2. Common async testing challenges
3. Check: ls test/support/deterministic_helpers.ex

Create test/support/deterministic_helpers.ex with:
1. wait_for/3 - polling with timeout
2. synchronize/1 - coordinate concurrent operations
3. ensure_pool_ready/3 - wait for pool initialization
4. inject_failure/3 - controlled failure injection

Show me:
1. Complete helper implementations
2. How wait_for handles timeouts
3. Synchronization approach
```

### Prompt 4.2.2 - Implement Failure Injection
```
Let's implement controlled failure injection.

First, understand failure types needed:
1. Port crashes
2. Timeouts
3. Network issues
4. Resource exhaustion

Implement injection functions:
1. simulate_port_crash/1 - kills worker port
2. simulate_timeout/2 - blocks operations
3. simulate_network_partition/2 - breaks communication
4. simulate_resource_exhaustion/1 - consumes resources
5. Helper to find worker processes

Show me:
1. All failure injection functions
2. How they target specific workers
3. Cleanup after injection
```

### Prompt 4.2.3 - Test Synchronization
```
Let's test the synchronization helpers.

Create test/support/deterministic_helpers_test.exs:
1. Test wait_for with various conditions
2. Test synchronize coordinates operations
3. Test timeout handling
4. Test failure injections work
5. Test deterministic execution

Verify:
1. No race conditions
2. Predictable timing
3. Proper error handling

Show me tests and results.
```

## Session 4.3: Enhanced Pool Test Helpers

### Prompt 4.3.1 - Update Pool Test Helpers
```
Let's enhance pool-specific test helpers.

First, read:
1. Current test/support/pool_test_helpers.ex
2. docs/V2_POOL_TECHNICAL_DESIGN_5_TEST_INFRASTRUCTURE.md pool helpers
3. New requirements from isolation framework

Update pool_test_helpers.ex with:
1. start_isolated_pool/1 using test isolation
2. concurrent_pool_operations/2 for parallel testing
3. with_pool_monitoring/2 to track metrics
4. simulate_pool_failure/3 for chaos testing

Show me:
1. Updated start_isolated_pool implementation
2. How it uses test isolation
3. Monitoring integration
```

### Prompt 4.3.2 - Implement Monitoring
```
Let's add pool monitoring for tests.

First, understand monitoring needs:
1. Operation counts
2. Error tracking
3. Performance metrics
4. Resource usage

Implement monitoring functions:
1. start_pool_monitor/1 - begins monitoring
2. monitor_loop/2 - collects metrics
3. stop_pool_monitor/1 - returns results
4. update_stats/3 - processes events
5. Metric aggregation logic

Show me:
1. Complete monitoring implementation
2. What metrics are collected
3. How to use in tests
```

### Prompt 4.3.3 - Add Chaos Testing
```
Let's implement chaos testing capabilities.

First, review chaos scenarios:
1. Cascading failures
2. Thundering herd
3. Slow workers
4. Memory leaks

Implement chaos functions:
1. simulate_cascade_failure/2 - sequential worker kills
2. simulate_thundering_herd/2 - burst of requests
3. simulate_slow_worker/2 - inject delays
4. simulate_memory_leak/2 - gradual memory growth

Show me:
1. All chaos simulation functions
2. How they create realistic failures
3. Monitoring during chaos
```

## Session 4.4: Unit Test Updates

### Prompt 4.4.1 - Create Worker State Machine Tests
```
Let's create isolated unit tests.

First, check existing tests:
1. ls test/dspex/python_bridge/*_test.exs
2. Identify tests needing isolation
3. Review isolated_test macro usage

Update worker_state_machine_test.exs:
1. Use isolated_test macro
2. Add property-based tests with StreamData
3. Test all state transitions
4. Test concurrent state access
5. Verify deterministic behavior

Show me:
1. Updated test file with isolation
2. Property test examples
3. Test results
```

### Prompt 4.4.2 - Create Error Handler Tests
```
Let's update error handler tests with isolation.

Update pool_error_handler_test.exs:
1. Convert to use isolated_test
2. Test each error category in isolation
3. Test concurrent error handling
4. Verify telemetry in isolation
5. Test error context preservation

Include:
1. Isolated telemetry handlers
2. Concurrent error scenarios
3. Resource cleanup verification

Show me updated tests and results.
```

## Session 4.5: Integration Test Suite

### Prompt 4.5.1 - Create Pool Integration Tests
```
Let's create comprehensive integration tests.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_5_TEST_INFRASTRUCTURE.md integration examples
2. Existing integration test patterns

Create test/dspex/python_bridge/pool_integration_test.exs:
1. Use isolated_test for each scenario
2. Test concurrent sessions
3. Test worker failure recovery
4. Test load balancing
5. Test session affinity
6. Test error propagation

Show me:
1. Complete test file structure
2. How isolation is used
3. Key test scenarios
```

### Prompt 4.5.2 - Multi-Layer Testing
```
Let's test across different layers.

Add layer-specific tests:
1. Layer 1 (mock) - fast, deterministic
2. Layer 2 (bridge mock) - protocol testing
3. Layer 3 (full) - real Python integration
4. Layer transition tests
5. Fallback between layers

For each layer:
1. Set appropriate configuration
2. Test layer-specific behavior
3. Verify isolation works
4. Check performance characteristics

Show me layer test implementation.
```

## Session 4.6: Performance Test Suite

### Prompt 4.6.1 - Create Performance Framework
```
Let's create performance testing infrastructure.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_5_TEST_INFRASTRUCTURE.md performance section
2. Benchee documentation for Elixir
3. Check: ls test/performance/

Create test/dspex/python_bridge/pool_performance_test.exs:
1. Module setup with @tag :performance
2. Benchmark configuration
3. warmup_pool/2 implementation
4. benchmark_pool_operations/2
5. Result analysis helpers

Show me:
1. Performance test structure
2. Benchmark configuration
3. Warmup approach
```

### Prompt 4.6.2 - Implement Benchmarks
```
Let's implement specific benchmarks.

First, understand metrics needed:
1. Throughput (ops/sec)
2. Latency distribution
3. Resource usage
4. Scalability curves

Implement benchmarks:
1. Single operation latency
2. Concurrent throughput test
3. Latency percentiles (p50, p90, p95, p99)
4. Memory usage over time
5. Pool scaling behavior

Show me:
1. Complete benchmark implementations
2. How to run with Benchee
3. Result interpretation
```

### Prompt 4.6.3 - Load Testing
```
Let's create realistic load tests.

Implement load test scenarios:
1. Gradual ramp to 1000 ops/sec
2. Sustained load for 5 minutes
3. Spike testing (sudden load increase)
4. Mixed operation types
5. Error injection under load

Include:
1. Client simulation
2. Request distribution
3. Metric collection
4. SLA verification

Show me load test implementation and run it.
```

## Session 4.7: Chaos Testing

### Prompt 4.7.1 - Create Chaos Test Suite
```
Let's implement chaos engineering tests.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_5_TEST_INFRASTRUCTURE.md chaos section
2. Chaos engineering principles
3. Pool failure modes

Create test/dspex/python_bridge/pool_chaos_test.exs:
1. Module with @tag :chaos
2. Cascading failure tests
3. Resource exhaustion tests
4. Network partition simulation
5. Byzantine failure tests

Show me:
1. Chaos test structure
2. Failure injection approach
3. System verification
```

### Prompt 4.7.2 - Implement Chaos Scenarios
```
Let's implement specific chaos scenarios.

Create realistic failure scenarios:
1. Kill 60% of workers rapidly
2. Introduce 100-500ms network delays
3. Corrupt 5% of messages randomly
4. Gradually exhaust memory
5. Combine multiple failure types

For each scenario:
1. Set up failure injection
2. Run normal workload
3. Monitor system response
4. Verify recovery
5. Check data integrity

Show me implementation and results.
```

## Session 4.8: CI/CD Integration

### Prompt 4.8.1 - Test Configuration
```
Let's configure tests for CI/CD.

First, read:
1. Current config/test.exs
2. CI requirements from design doc
3. Environment-specific needs

Update config/test.exs:
1. Layer-specific configurations
2. Performance thresholds
3. Test isolation settings
4. Timeout configurations
5. Logging levels for CI

Show me:
1. Updated configuration
2. How layers are configured
3. CI-specific settings
```

### Prompt 4.8.2 - Create Test Scripts
```
Let's create test execution scripts.

Create scripts in scripts/ directory:
1. run_unit_tests.sh - fast feedback
2. run_integration_tests.sh - by layer
3. run_performance_tests.sh - with reporting
4. run_chaos_tests.sh - optional
5. run_all_tests.sh - complete suite

Each script should:
1. Set proper environment
2. Run specific test subset
3. Handle failures gracefully
4. Generate reports

Show me script implementations.
```

## Session 4.9: Test Documentation

### Prompt 4.9.1 - Testing Guide
```
Let's create comprehensive testing documentation.

Create docs/TESTING_GUIDE.md covering:
1. Test architecture overview
2. Test isolation framework usage
3. Writing isolated tests
4. Performance testing guide
5. Chaos testing procedures
6. CI/CD integration

Include:
1. Code examples
2. Best practices
3. Common patterns
4. Troubleshooting

Show me documentation outline and key sections.
```

### Prompt 4.9.2 - Test Patterns
```
Let's document test patterns and anti-patterns.

Create docs/TEST_PATTERNS.md with:
1. Proper test isolation examples
2. Deterministic test patterns
3. Performance test design
4. Common pitfalls to avoid
5. Best practices checklist

Include:
1. Good vs bad examples
2. Why patterns matter
3. Migration guide for old tests

Show me pattern documentation.
```

## Session 4.10: Validation and Migration

### Prompt 4.10.1 - Run Complete Test Suite
```
Let's validate the entire test suite.

Execute comprehensive test run:
1. Run: mix test (all unit tests)
2. Run: ./scripts/run_integration_tests.sh
3. Run: ./scripts/run_performance_tests.sh
4. Run: ./scripts/run_chaos_tests.sh
5. Generate coverage: mix coveralls.html

Check:
1. All tests passing?
2. Coverage acceptable?
3. Performance meets targets?
4. No test interdependencies?

Show me results summary.
```

### Prompt 4.10.2 - Phase 4 Completion
```
Let's validate Phase 4 completion.

Create validation checklist:
1. Test isolation framework working?
2. All tests converted to isolation?
3. Deterministic execution verified?
4. Performance baselines established?
5. CI/CD integration complete?
6. Documentation comprehensive?

Generate Phase 4 report:
1. Components implemented
2. Test statistics
3. Performance baselines
4. Known issues
5. Migration guide

Show me validation results and report.
```

## Session 4.11: Test Maintenance

### Prompt 4.11.1 - Create Test Utilities
```
Let's create additional test utilities.

Create test/support/test_utilities.ex with:
1. Test data generators (using StreamData)
2. Custom assertions for pool operations
3. Test result reporters
4. Performance analyzers
5. Failure analyzers

Show me:
1. Utility implementations
2. How to use them
3. Integration with existing tests
```

### Prompt 4.11.2 - Continuous Improvement
```
Let's set up continuous test improvement.

Implement monitoring for:
1. Flaky test detection
2. Performance regression alerts
3. Coverage tracking over time
4. Test execution time trends
5. Automated test updates

Create scripts/test_health.sh that:
1. Identifies flaky tests
2. Reports slow tests
3. Checks coverage trends
4. Suggests improvements

Show me implementation and sample output.
```