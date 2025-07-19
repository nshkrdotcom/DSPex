# Task: NATIVE.4 - Metrics Collection System

## Context
You are implementing the metrics collection system for DSPex, which tracks performance, usage patterns, and optimization effectiveness. This system is crucial for the cognitive orchestration capabilities that allow DSPex to learn and adapt.

## Required Reading

### 1. Cognitive Orchestration Architecture
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/01_CORE_ARCHITECTURE.md`
  - Section: "Cognitive Telemetry Layer"
  - Focus on how metrics feed into adaptation

### 2. Telemetry Patterns from libStaging
- **File**: `/home/home/p/g/n/dspex/docs/LIBSTAGING_PATTERNS_FOR_COGNITIVE_ORCHESTRATION.md`
  - Lines 176-189: Performance tracking patterns
  - Lines 185-189: Telemetry integration examples

### 3. Existing Metrics Module
- **File**: `/home/home/p/g/n/dspex/lib/dspex/native/metrics.ex`
  - Review current implementation approach
  - Note integration points with other modules

### 4. Requirements Reference
- **File**: `/home/home/p/g/n/dspex/docs/specs/immediate_implementation/REQUIREMENTS.md`
  - Section: "Non-Functional Requirements" - NFR.5 (Observability)
  - Section: "Future-Ready Requirements" - FR.1 (Consciousness hooks)

### 5. Success Criteria Examples
- **File**: `/home/home/p/g/n/dspex/docs/specs/dspex_cognitive_orchestration/06_SUCCESS_CRITERIA.md`
  - Lines covering telemetry tests (search for "telemetry")
  - Examples of metrics analysis and adaptation

## Implementation Requirements

### Core Metrics Types
1. **Performance Metrics**
   - Execution duration (per operation, per stage)
   - Latency breakdown (queue time, execution time, response time)
   - Throughput (requests/second)
   - Resource usage (memory, CPU)

2. **Quality Metrics**
   - Validation success/failure rates
   - LLM token usage
   - Output quality scores (when available)
   - Retry counts and reasons

3. **Pattern Metrics**
   - Operation frequency
   - Parameter distributions
   - Error patterns
   - Usage patterns by session

4. **Optimization Metrics**
   - Variable optimization history
   - Strategy effectiveness
   - Adaptation success rates
   - Learning convergence

### Telemetry Events Structure
```elixir
# Event naming convention: [:dspex, component, action]
[:dspex, :router, :route_selected]
[:dspex, :native, :signature_parsed]
[:dspex, :llm, :adapter_selected]
[:dspex, :pipeline, :stage_completed]
[:dspex, :optimization, :variable_updated]
```

### Implementation Structure
```
lib/dspex/native/
├── metrics.ex                    # Main metrics module
├── metrics/
│   ├── collector.ex             # Event collection
│   ├── aggregator.ex            # Metric aggregation
│   ├── analyzer.ex              # Pattern analysis
│   └── storage.ex               # ETS-based storage
```

## Acceptance Criteria
- [ ] Telemetry events defined for all major operations
- [ ] Metrics collector captures all events with minimal overhead
- [ ] Aggregator provides time-windowed metrics (1min, 5min, 1hour)
- [ ] Pattern analyzer detects trends and anomalies
- [ ] Storage system with automatic cleanup of old data
- [ ] Export interface for external monitoring systems
- [ ] Performance overhead <1% on operations
- [ ] Integration with cognitive orchestration for adaptation triggers

## Telemetry Event Examples
```elixir
# Router selection event
:telemetry.execute(
  [:dspex, :router, :route_selected],
  %{duration: 0.5},
  %{
    operation: "predict",
    selected: :native,
    reason: :performance,
    alternatives: [:python]
  }
)

# LLM execution event
:telemetry.execute(
  [:dspex, :llm, :execution_complete],
  %{duration: 150, tokens: 245},
  %{
    adapter: "instructor_lite",
    model: "gpt-3.5-turbo",
    success: true
  }
)
```

## Storage Schema
```elixir
# ETS tables
:dspex_metrics_current    # Current window metrics
:dspex_metrics_historical # Historical aggregates
:dspex_metrics_patterns   # Detected patterns

# Metric record structure
%{
  event: [:dspex, :router, :route_selected],
  timestamp: ~U[2024-01-20 10:30:00Z],
  measurements: %{duration: 0.5},
  metadata: %{operation: "predict", selected: :native},
  window: :current
}
```

## Analysis Functions
```elixir
# Required analysis functions
- calculate_percentiles(metric, percentiles)
- detect_anomalies(metric, window)
- analyze_trends(metric, periods)
- find_patterns(events, window)
- suggest_optimizations(metrics)
```

## Testing Requirements
Create tests in:
- `test/dspex/native/metrics_test.exs`
- `test/dspex/native/metrics/` (one file per sub-module)

Test scenarios:
- High-volume event handling (1000+ events/second)
- Memory usage under load
- Correct aggregation across time windows
- Pattern detection accuracy
- Integration with adaptation system

## Dependencies
- Requires CORE.1 to be complete
- Integrates with all other components
- Will be used by cognitive orchestration layer

## Time Estimate
4 hours total:
- 1 hour: Core telemetry event setup
- 1 hour: Collector and aggregator
- 1 hour: Pattern analyzer
- 1 hour: Testing and optimization

## Notes
- Use `:telemetry` library for standard Elixir patterns
- Consider using `:telemetry_metrics` for aggregation
- Ensure minimal performance impact
- Design for future export to Prometheus/StatsD
- Include hooks for consciousness integration (metadata enrichment)