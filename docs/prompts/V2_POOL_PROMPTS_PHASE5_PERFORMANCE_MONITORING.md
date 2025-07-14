# V2 Pool Implementation Prompts - Phase 5: Performance Optimization and Monitoring

## Session 5.1: Pool Optimizer

### Prompt 5.1.1 - Create Pool Optimizer
```
We're implementing Phase 5 of the V2 Pool design, specifically performance optimization.
Current status: Phase 4 test infrastructure complete
Today's goal: Implement dynamic pool optimization

Create lib/dspex/python_bridge/pool_optimizer.ex from Design Doc 6. Start with:
1. GenServer structure and state
2. Metrics history tracking
3. Optimization scheduling
4. Configuration management

Show the initial implementation.
```

### Prompt 5.1.2 - Implement Optimization Logic
```
Implement the core optimization functions:
1. perform_optimization/1 to analyze and adjust
2. analyze_metrics/1 for pattern detection
3. determine_optimal_config/2 for decisions
4. scale_up/2 and scale_down/2 logic

Include intelligent scaling decisions.
```

### Prompt 5.1.3 - Add Metric Analysis
```
Implement sophisticated metric analysis:
1. Utilization patterns
2. Queue depth trends
3. Wait time analysis
4. Error rate correlation
5. Throughput optimization

Test with various workload patterns.
```

### Prompt 5.1.4 - Test Optimizer
```
Create tests for the optimizer:
1. Scales up under high load
2. Scales down when underutilized
3. Respects min/max boundaries
4. Handles edge cases
5. Makes timely decisions

Verify optimization improves performance.
```

## Session 5.2: Pre-warming Strategies

### Prompt 5.2.1 - Create Pool Warmer
```
Create lib/dspex/python_bridge/pool_warmer.ex from Design Doc 6:
1. Pre-warming command definitions
2. Multiple warming strategies
3. Worker coordination
4. Progress tracking

This reduces cold start latency.
```

### Prompt 5.2.2 - Implement Warming Strategies
```
Implement different warming strategies:
1. warm_parallel/2 for fast startup
2. warm_sequential/2 for resource-constrained
3. warm_staged/2 for gradual warming
4. Custom command support

Test each strategy's effectiveness.
```

### Prompt 5.2.3 - Integration Testing
```
Test pool warming integration:
1. Cold pool vs warm pool latency
2. Resource usage during warming
3. Warming failure handling
4. Partial warming scenarios
5. Performance impact measurement

Verify significant latency improvement.
```

## Session 5.3: Telemetry Integration

### Prompt 5.3.1 - Create Telemetry Module
```
Create lib/dspex/python_bridge/telemetry.ex from Design Doc 6:
1. Event definitions
2. Default handlers
3. Span helper for timing
4. Event namespacing

This provides comprehensive observability.
```

### Prompt 5.3.2 - Instrument Pool Operations
```
Add telemetry throughout the pool:
1. Worker lifecycle events
2. Operation timing
3. Queue depth reporting
4. Error event emission
5. Performance metrics

Verify all key operations emit events.
```

### Prompt 5.3.3 - Create Telemetry Handlers
```
Implement telemetry handlers:
1. Logger handler for debugging
2. Metrics handler for aggregation
3. Reporter handler for external systems
4. Alert handler for thresholds

Test handlers don't impact performance.
```

## Session 5.4: Metrics Collection

### Prompt 5.4.1 - Create Metrics Collector
```
Create lib/dspex/python_bridge/metrics_collector.ex from Design Doc 6:
1. ETS-based metric storage
2. Periodic collection
3. Metric aggregation
4. History management

This centralizes metric gathering.
```

### Prompt 5.4.2 - Implement Collection Logic
```
Implement metric collection:
1. Real-time metric updates
2. Periodic snapshots
3. Statistical calculations
4. Percentile tracking
5. Health score computation

Include efficient data structures.
```

### Prompt 5.4.3 - Add Derived Metrics
```
Calculate derived metrics:
1. Utilization percentage
2. Throughput (ops/sec)
3. Average latency
4. Error rates
5. Queue wait times

Test calculations are accurate.
```

## Session 5.5: Monitoring Dashboard

### Prompt 5.5.1 - Create LiveView Dashboard
```
Create lib/dspex_web/live/pool_dashboard_live.ex from Design Doc 6:
1. Real-time metric display
2. Pool selection
3. Time range controls
4. Chart rendering
5. Alert indicators

This provides operational visibility.
```

### Prompt 5.5.2 - Implement Visualizations
```
Add data visualizations:
1. Utilization gauge
2. Throughput line chart
3. Latency histogram
4. Error rate trends
5. Pool health summary

Use JavaScript hooks for charts.
```

### Prompt 5.5.3 - Test Dashboard
```
Test the monitoring dashboard:
1. Real-time updates work
2. Historical data displays correctly
3. Pool switching works
4. Performance is acceptable
5. Mobile responsive

Verify it's useful for operations.
```

## Session 5.6: Performance Tuning

### Prompt 5.6.1 - Configuration Optimization
```
Create optimal configurations for different workloads:
1. High-throughput config
2. Low-latency config
3. Balanced config
4. Resource-constrained config
5. Development config

Test each configuration's characteristics.
```

### Prompt 5.6.2 - Benchmark Suite
```
Create comprehensive benchmarks:
1. Single operation latency
2. Concurrent operation throughput
3. Queue behavior under load
4. Worker utilization patterns
5. Memory usage over time

Establish performance baselines.
```

### Prompt 5.6.3 - Optimization Validation
```
Validate optimizations work:
1. Compare before/after metrics
2. Test under various loads
3. Verify no regressions
4. Check resource efficiency
5. Confirm SLA compliance

Document performance gains.
```

## Session 5.7: Production Readiness

### Prompt 5.7.1 - Production Configuration
```
Create production configuration:
1. Optimal pool sizes
2. Timeout settings
3. Health check intervals
4. Monitoring thresholds
5. Alert configurations

Base on benchmark results.
```

### Prompt 5.7.2 - Operational Procedures
```
Document operational procedures:
1. Pool startup sequence
2. Warming procedures
3. Monitoring checklist
4. Performance tuning guide
5. Troubleshooting steps

Create OPERATIONS.md.
```

## Session 5.8: Load Testing

### Prompt 5.8.1 - Production Load Test
```
Run production-scale load tests:
1. 10,000 concurrent sessions
2. 5,000 ops/sec sustained
3. 24-hour stability test
4. Failure injection
5. Recovery verification

Verify production readiness.
```

### Prompt 5.8.2 - Performance Report
```
Generate comprehensive performance report:
1. Latency percentiles (p50, p90, p95, p99)
2. Throughput measurements
3. Resource utilization
4. Error rates and types
5. Optimization recommendations

Include comparison with requirements.
```

## Session 5.9: Integration Testing

### Prompt 5.9.1 - End-to-End Performance
```
Test complete system performance:
1. API to pool to Python flow
2. Session management overhead
3. Error handling impact
4. Monitoring overhead
5. Total system latency

Identify any bottlenecks.
```

### Prompt 5.9.2 - Optimization Verification
```
Verify all optimizations integrate well:
1. Pool optimizer decisions
2. Pre-warming effectiveness
3. Telemetry overhead
4. Metric collection impact
5. Dashboard performance

Ensure no negative interactions.
```

## Session 5.10: Documentation and Handoff

### Prompt 5.10.1 - Performance Documentation
```
Create comprehensive performance docs:
1. Architecture performance characteristics
2. Tuning guide with examples
3. Monitoring setup instructions
4. Alert configuration guide
5. Capacity planning guide

Include real-world scenarios.
```

### Prompt 5.10.2 - Phase 5 Completion
```
Validate Phase 5 completion:
1. All performance targets met
2. Monitoring fully operational
3. Optimization automated
4. Documentation complete
5. Production ready

Create final implementation report.
```

## Session 5.11: Performance Maintenance

### Prompt 5.11.1 - Continuous Optimization
```
Set up continuous optimization:
1. Automated performance tests
2. Regression detection
3. Optimization suggestions
4. Capacity forecasting
5. Trend analysis

Document the process.
```

### Prompt 5.11.2 - Final Validation
```
Final system validation:
1. Run all test suites
2. Verify performance SLAs
3. Check monitoring completeness
4. Validate documentation
5. Prepare deployment checklist

System is ready for migration.
```