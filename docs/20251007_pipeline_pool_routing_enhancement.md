# Pipeline Pool Routing Enhancement (Future Feature)

**Date:** 2025-10-07
**Status:** Design Phase
**Priority:** Medium
**Scope:** Pipeline execution optimization via specialized worker pools

## Overview

Implement intelligent routing of Python DSPy module executions to specialized worker pools based on module characteristics (optimizer, neural, general).

## Current State

Partial implementation exists:
- `select_pool_for_module/1` categorizes modules (lib/dspex/pipeline.ex:281-287)
- Returns `:optimizer`, `:neural`, or `:general` pool atoms
- **Not connected to execution layer** - variable assigned but unused

## Design

### Pool Categories

```elixir
:optimizer  # MIPRO, Optimizer, Bootstrap - CPU-intensive, long-running
:neural     # ColBERT, Neural, Embed - GPU/memory-intensive
:general    # Default - standard DSPy modules
```

### Architecture

```
Pipeline.execute_step/3
  └─> select_pool_for_module/1 → pool_name
      └─> Bridge.call_dspy/5 (new signature: +pool param)
          └─> SessionPool.checkout/2 (pool-aware)
              └─> Snakepit worker from appropriate pool
```

### Pool Configuration

```elixir
config :dspex, :pools,
  optimizer: [size: 2, max_overflow: 1],    # Fewer, long-lived
  neural: [size: 4, max_overflow: 2],       # GPU-bound parallelism
  general: [size: 8, max_overflow: 4]       # Standard workload
```

## Use Cases

### UC1: Optimizer Isolation
- **Problem:** MIPRO optimization blocks general queries
- **Solution:** Dedicated pool prevents head-of-line blocking
- **Benefit:** 10x improvement in concurrent request latency

### UC2: GPU Resource Management
- **Problem:** Multiple neural models compete for GPU memory
- **Solution:** Neural pool with GPU-aware scheduling
- **Benefit:** Predictable OOM prevention, better throughput

### UC3: Cost Optimization
- **Problem:** Over-provisioned workers for mixed workloads
- **Solution:** Right-sized pools per workload type
- **Benefit:** 30-40% reduction in idle Python processes

## Implementation Tasks

1. **SessionPool enhancement** (lib/dspex/session_pool.ex)
   - Multi-pool registry: `{:via, Registry, {DSPex.PoolRegistry, pool_name}}`
   - Pool-aware checkout/checkin

2. **Bridge API update** (lib/dspex/bridge.ex)
   - Add `pool` option to `call_dspy/5`
   - Thread through to SessionPool

3. **Pipeline integration** (lib/dspex/pipeline.ex:179)
   - Uncomment pool variable
   - Pass to Bridge: `DSPex.Bridge.call_dspy(..., pool: pool)`

4. **Supervision tree** (lib/dspex/application.ex)
   - Start 3 pool supervisors
   - Dynamic config from application env

5. **Telemetry**
   - Per-pool metrics: queue depth, utilization, latency
   - Event: `[:dspex, :pool, :checkout]`

## Testing Strategy

- **Unit:** Pool selection logic correctness
- **Integration:** Multi-pool checkout/isolation
- **Performance:** Benchmark optimizer blocking scenarios
- **Chaos:** Pool exhaustion, worker crashes

## Migration Path

1. **Phase 1:** Enable pools with identical configs (behavior-preserving)
2. **Phase 2:** Tune pool sizes based on telemetry
3. **Phase 3:** Add advanced features (priorities, backpressure)

## Dependencies

- NimblePool (already in use)
- Registry for multi-pool naming
- Telemetry for observability

## Risks

- **Complexity:** 3x supervision overhead
- **Config tuning:** Requires production profiling
- **Starvation:** Misconfigured pools could starve workloads

## Open Questions

1. Should pools share overflow capacity?
2. GPU affinity for neural pool workers?
3. Dynamic pool resizing based on load?

## References

- Existing pooling: `docs/POOL_IMPLEMENTATION_GUIDE.md`
- Session management: `docs/20250716_v3_pooler_design/`
- Current incomplete code: `lib/dspex/pipeline.ex:179,281-287`
