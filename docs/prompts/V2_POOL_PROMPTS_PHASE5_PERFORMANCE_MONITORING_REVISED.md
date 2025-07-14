# V2 Pool Implementation Prompts - Phase 5: Performance Monitoring (REVISED)

## Session 5.1: Telemetry Infrastructure

### Prompt 5.1.1 - Create Telemetry Module
```
We're implementing Phase 5 of the V2 Pool design, specifically performance monitoring.

First, read these files to understand requirements:
1. Read docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md section "Telemetry Infrastructure"
2. Check existing telemetry usage: grep -r ":telemetry" lib/
3. Review telemetry best practices in Elixir
4. Check: ls lib/dspex/python_bridge/telemetry.ex

Create lib/dspex/python_bridge/telemetry.ex with:
1. Module declaration with proper documentation
2. Event name definitions as constants
3. Event documentation for each type
4. Helper functions for emitting events
5. Metadata standardization

Show me:
1. Complete module structure
2. All event constants defined
3. Helper function signatures
```

### Prompt 5.1.2 - Implement Event Emitters
```
Let's implement telemetry event emission helpers.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md telemetry events table
2. Your current telemetry.ex file
3. Common metadata patterns from existing events

Implement these emission functions:
1. execute_pool_operation/3 - wraps operations with timing
2. emit_worker_event/3 - worker state changes
3. emit_error_event/3 - error occurrences
4. emit_recovery_event/3 - recovery actions
5. emit_resource_event/3 - resource usage

Show me:
1. All emission function implementations
2. How timing is captured
3. Metadata structure for each event type
```

### Prompt 5.1.3 - Add Pool Integration
```
Let's integrate telemetry into the pool.

First, read:
1. Current lib/dspex/python_bridge/session_pool_v2.ex
2. Key operation points that need telemetry
3. How to minimize performance impact

Update SessionPoolV2 to emit events:
1. Pool initialization
2. Operation execution (with timing)
3. Worker checkout/checkin
4. Error occurrences
5. Pool size changes

Show me:
1. Where telemetry calls are added
2. The updated execute_in_session with timing
3. How metadata is structured
```

### Prompt 5.1.4 - Test Telemetry
```
Let's test telemetry event emission.

First, check test helpers:
1. ls test/support/telemetry_helpers.ex
2. If missing, we'll create it

Create test/dspex/python_bridge/telemetry_test.exs:
1. Set up telemetry handlers in tests
2. Test each event type is emitted
3. Verify metadata completeness
4. Test timing accuracy
5. Test error event details

Include:
1. Helper to capture events
2. Assertions on event data
3. Performance overhead check

Run tests and show results.
```

## Session 5.2: Metrics Collection

### Prompt 5.2.1 - Create Metrics Collector
```
Let's create the metrics collection system.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md section "Metrics Collection"
2. Understand ETS-based storage approach
3. Check: ls lib/dspex/python_bridge/metrics_collector.ex

Create lib/dspex/python_bridge/metrics_collector.ex with:
1. GenServer setup
2. ETS table creation for metrics
3. Telemetry handler attachment
4. State structure for aggregation
5. Periodic aggregation scheduling

Show me:
1. Complete GenServer structure
2. ETS table schema
3. How telemetry handlers are attached
```

### Prompt 5.2.2 - Implement Aggregation
```
Let's implement metrics aggregation logic.

First, understand:
1. Time window aggregation (1min, 5min, 15min)
2. Percentile calculations needed
3. Counter and gauge differences
4. Memory efficiency requirements

Implement aggregation functions:
1. handle_event/4 for telemetry events
2. aggregate_metrics/1 for time windows
3. calculate_percentiles/1 for latencies
4. update_counters/2 for counts
5. store_aggregated/2 for ETS updates

Show me:
1. Complete aggregation logic
2. How percentiles are calculated
3. ETS update patterns
```

### Prompt 5.2.3 - Add Query Interface
```
Let's add metrics query capabilities.

First, review:
1. Your current metrics_collector.ex
2. Common query patterns needed
3. Performance considerations

Implement query functions:
1. get_current_metrics/0 - latest snapshot
2. get_metrics_range/2 - time range query
3. get_worker_metrics/1 - per-worker stats
4. get_error_rates/1 - error statistics
5. get_performance_summary/0 - overview

Show me:
1. All query function implementations
2. How ETS selects are optimized
3. Response format examples
```

### Prompt 5.2.4 - Test Metrics Collection
```
Let's test the metrics collector.

Create test/dspex/python_bridge/metrics_collector_test.exs:
1. Test event handling updates metrics
2. Test aggregation windows work correctly
3. Test percentile calculations
4. Test query functions return correct data
5. Test memory usage stays bounded

Include performance tests:
1. High event rate handling
2. Query performance
3. Memory growth monitoring

Run tests and show results.
```

## Session 5.3: Performance Dashboard

### Prompt 5.3.1 - Create Dashboard Module
```
Let's create a performance dashboard.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md section "Performance Dashboard"
2. Check if LiveView is available: grep -r "LiveView" lib/
3. Alternative: terminal-based dashboard

Create lib/dspex/python_bridge/performance_dashboard.ex:
1. Module structure for reporting
2. ASCII chart generation functions
3. Table formatting helpers
4. Color coding for thresholds
5. Refresh scheduling

Show me:
1. Complete module structure
2. How data is formatted
3. Example output format
```

### Prompt 5.3.2 - Implement Visualizations
```
Let's implement dashboard visualizations.

First, understand visualization needs:
1. Throughput over time (line chart)
2. Latency distribution (histogram)
3. Error rate trends
4. Worker utilization
5. Resource usage gauges

Implement display functions:
1. render_throughput_chart/1
2. render_latency_histogram/1
3. render_error_trends/1
4. render_worker_table/1
5. render_resource_gauges/1

Show me:
1. ASCII chart implementations
2. How data is scaled for display
3. Example rendered output
```

### Prompt 5.3.3 - Add Real-time Updates
```
Let's add real-time dashboard updates.

First, review:
1. Current dashboard structure
2. Terminal update techniques
3. ANSI escape codes for updates

Implement real-time features:
1. start_dashboard/1 to begin display
2. refresh_loop/1 for periodic updates
3. clear_and_render/1 for smooth updates
4. handle_input/1 for interactivity
5. stop_dashboard/0 for cleanup

Show me:
1. Complete real-time implementation
2. How terminal is updated
3. Interactive commands available
```

## Session 5.4: Alerting System

### Prompt 5.4.1 - Create Alert Manager
```
Let's create the alerting system.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md section "Alerting System"
2. Alert conditions and thresholds
3. Check: ls lib/dspex/python_bridge/alert_manager.ex

Create lib/dspex/python_bridge/alert_manager.ex:
1. GenServer for alert management
2. Alert rule definitions
3. Threshold configuration
4. Alert state tracking
5. Notification dispatching

Show me:
1. Complete module structure
2. Alert rule format
3. How thresholds are configured
```

### Prompt 5.4.2 - Implement Alert Rules
```
Let's implement alert evaluation logic.

First, understand alert types:
1. Threshold alerts (simple comparison)
2. Rate alerts (change over time)
3. Anomaly alerts (deviation from normal)
4. Composite alerts (multiple conditions)

Implement alert evaluation:
1. evaluate_rules/1 main evaluation loop
2. check_threshold/2 for simple alerts
3. check_rate_change/2 for trends
4. check_anomaly/2 for deviations
5. Alert history tracking

Show me:
1. All evaluation functions
2. How state changes are detected
3. Alert deduplication logic
```

### Prompt 5.4.3 - Add Notification Channels
```
Let's implement notification channels.

First, check available options:
1. Logger for local alerts
2. File-based for persistence
3. Webhook support if configured
4. Email if SMTP available

Implement notification functions:
1. send_alert/2 dispatcher
2. log_alert/1 for Logger
3. write_alert_file/1 for persistence
4. post_webhook/2 if configured
5. Rate limiting for notifications

Show me:
1. All notification implementations
2. How rate limiting works
3. Alert formatting for each channel
```

## Session 5.5: Resource Monitoring

### Prompt 5.5.1 - Create Resource Monitor
```
Let's monitor system resource usage.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md resource monitoring section
2. Erlang system monitoring APIs
3. Check: ls lib/dspex/python_bridge/resource_monitor.ex

Create lib/dspex/python_bridge/resource_monitor.ex:
1. GenServer for resource tracking
2. Memory usage collection
3. Process count monitoring
4. Port usage tracking
5. ETS table monitoring

Show me:
1. Complete module implementation
2. What resources are tracked
3. Collection frequency setup
```

### Prompt 5.5.2 - Python Process Monitoring
```
Let's monitor Python process resources.

First, understand:
1. How to get OS process info
2. Python process identification
3. Resource limits to track

Implement Python monitoring:
1. get_python_processes/0 to find processes
2. collect_process_stats/1 for each process
3. Monitor CPU, memory, file descriptors
4. Track process lifecycle
5. Detect zombie processes

Show me:
1. Process discovery implementation
2. Stats collection approach
3. How to handle missing processes
```

### Prompt 5.5.3 - Resource Alerts
```
Let's add resource-based alerts.

Update alert_manager.ex with resource alerts:
1. High memory usage alert
2. Process count threshold
3. Port exhaustion warning
4. ETS table size alerts
5. Python process crash detection

Include:
1. Dynamic threshold calculation
2. Trend-based alerts
3. Recovery detection

Show me updated alert rules and tests.
```

## Session 5.6: Performance Optimization

### Prompt 5.6.1 - Create Optimization Advisor
```
Let's create performance optimization recommendations.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md optimization section
2. Common performance patterns
3. Check: ls lib/dspex/python_bridge/optimization_advisor.ex

Create lib/dspex/python_bridge/optimization_advisor.ex:
1. Analysis functions for metrics
2. Pattern detection algorithms
3. Recommendation generation
4. Priority scoring
5. Action suggestions

Show me:
1. Complete advisor module
2. What patterns are detected
3. How recommendations are scored
```

### Prompt 5.6.2 - Implement Analysis
```
Let's implement performance analysis.

First, understand patterns to detect:
1. Underutilized workers
2. Overloaded workers
3. Memory leaks
4. Slow operations
5. Error hotspots

Implement detection functions:
1. analyze_worker_utilization/1
2. detect_memory_trends/1
3. find_slow_operations/1
4. identify_error_patterns/1
5. generate_recommendations/1

Show me:
1. All analysis implementations
2. Detection thresholds
3. Example recommendations
```

### Prompt 5.6.3 - Auto-tuning
```
Let's implement basic auto-tuning.

First, review safe tuning parameters:
1. Pool size adjustments
2. Timeout configurations
3. Health check intervals
4. Retry delays

Implement auto-tuning:
1. Safe parameter ranges
2. Gradual adjustment logic
3. Performance validation
4. Rollback capability
5. Tuning history

Show me:
1. Auto-tuning implementation
2. Safety constraints
3. How changes are applied
```

## Session 5.7: Integration Testing

### Prompt 5.7.1 - Performance Test Suite
```
Let's create comprehensive performance tests.

First, read:
1. docs/V2_POOL_TECHNICAL_DESIGN_6_PERFORMANCE_MONITORING.md test scenarios
2. Existing performance test patterns
3. Check: ls test/performance/

Create test/dspex/python_bridge/performance_monitoring_test.exs:
1. Test telemetry overhead
2. Test metrics accuracy
3. Test dashboard rendering
4. Test alert triggering
5. Load test monitoring system

Show me:
1. Complete test suite
2. How load is generated
3. Performance baselines
```

### Prompt 5.7.2 - Benchmark Monitoring
```
Let's benchmark the monitoring system.

Create benchmarks for:
1. Telemetry event processing rate
2. Metrics query performance
3. Dashboard render time
4. Alert evaluation speed
5. Memory overhead

Use Benchee to measure:
1. Operations per second
2. Memory allocations
3. Latency percentiles

Run benchmarks and show results.
```

## Session 5.8: Production Readiness

### Prompt 5.8.1 - Configuration Management
```
Let's set up monitoring configuration.

First, read:
1. Current config files: ls config/
2. Environment-specific needs
3. Configuration best practices

Create monitoring configuration:
1. Telemetry event filtering
2. Metrics retention periods
3. Alert threshold defaults
4. Dashboard refresh rates
5. Resource limits

Show me:
1. Configuration structure
2. Environment overrides
3. Runtime configuration
```

### Prompt 5.8.2 - Monitoring the Monitors
```
Let's ensure monitoring system health.

Add self-monitoring for:
1. Metrics collector health
2. Alert manager status
3. Memory usage of monitoring
4. Event processing lag
5. Dashboard responsiveness

Implement health checks:
1. Periodic self-check
2. Deadlock detection
3. Memory limit enforcement
4. Graceful degradation

Show me implementation and tests.
```

## Session 5.9: Documentation

### Prompt 5.9.1 - Monitoring Guide
```
Let's create monitoring documentation.

First, review what to document:
1. Available metrics
2. Alert configurations
3. Dashboard usage
4. Troubleshooting
5. Performance tuning

Create docs/MONITORING_GUIDE.md with:
1. Architecture overview
2. Metrics reference
3. Alert rule examples
4. Dashboard commands
5. Common scenarios
6. Performance tips

Show me:
1. Documentation outline
2. Key sections
3. Example configurations
```

### Prompt 5.9.2 - Operations Playbook
```
Let's create an operations playbook.

Create docs/OPERATIONS_PLAYBOOK.md with:
1. Daily monitoring tasks
2. Performance investigation steps
3. Alert response procedures
4. Capacity planning guide
5. Optimization workflows

Include:
1. Checklists
2. Decision trees
3. Command examples
4. Escalation paths

Show me playbook content.
```

## Session 5.10: Phase Validation

### Prompt 5.10.1 - Run Full Test Suite
```
Let's validate all monitoring components.

Execute comprehensive tests:
1. Run: mix test test/dspex/python_bridge/ --tag monitoring
2. Run performance benchmarks
3. Test dashboard interactively
4. Trigger sample alerts
5. Check resource usage

Verify:
1. All tests passing?
2. Performance acceptable?
3. Alerts working?
4. Dashboard readable?
5. No memory leaks?

Show me results summary.
```

### Prompt 5.10.2 - Phase 5 Completion
```
Let's validate Phase 5 completion.

Create validation checklist:
1. Telemetry infrastructure complete?
2. Metrics collection working?
3. Dashboard functional?
4. Alerts configured?
5. Resource monitoring active?
6. Documentation complete?

Generate Phase 5 report:
1. Components implemented
2. Performance metrics
3. Alert rules defined
4. Known limitations
5. Production readiness

Show me validation results and report.
```

## Session 5.11: Performance Tuning

### Prompt 5.11.1 - Optimize Hot Paths
```
Let's optimize performance-critical paths.

First, profile the system:
1. Identify hot paths with :fprof
2. Check telemetry overhead
3. Review metrics collection cost
4. Measure alert evaluation time

Optimize:
1. Reduce allocations in hot paths
2. Batch telemetry events
3. Use ETS match specs efficiently
4. Cache computed values

Show me:
1. Profiling results
2. Optimizations applied
3. Performance improvements
```

### Prompt 5.11.2 - Long-term Testing
```
Let's run extended monitoring tests.

Set up long-running test:
1. Run pool under load for 1 hour
2. Monitor metrics growth
3. Check for memory leaks
4. Verify alert accuracy
5. Test dashboard stability

Track:
1. Memory usage over time
2. Metrics query performance
3. Alert false positive rate
4. System resource usage

Show me results and any issues found.
```