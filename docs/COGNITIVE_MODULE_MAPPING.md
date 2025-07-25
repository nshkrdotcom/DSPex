# Cognitive Module Mapping - Current → Target Architecture

## Overview

This document maps current DSPy bridge functionality to the target cognitive-ready architecture, providing a detailed guide for the migration process.

## Module Migration Map

### DSPex.Bridge → Cognitive Architecture

| Current Function | Current Location | Target Module | Target Function | Migration Notes |
|------------------|------------------|---------------|-----------------|-----------------|
| `call_dspy/5` | `DSPex.Bridge` | `SnakepitGrpcBridge.Schema.DSPy` | `call_dspy/5` | Move + add performance telemetry |
| `create_instance/3` | `DSPex.Bridge` | `SnakepitGrpcBridge.Schema.DSPy` | `create_instance/3` | Move + add instance tracking |
| `call_method/4` | `DSPex.Bridge` | `SnakepitGrpcBridge.Schema.DSPy` | `call_method/4` | Move + add method call telemetry |
| `discover_schema/2` | `DSPex.Bridge` | `SnakepitGrpcBridge.Schema.DSPy` | `discover_schema/2` | Move + add caching + telemetry |
| `generate_docs/2` | `DSPex.Bridge` | `SnakepitGrpcBridge.Schema.DSPy` | `generate_docs/2` | Move + add documentation metrics |
| `defdsyp/2,3` | `DSPex.Bridge` | `SnakepitGrpcBridge.Codegen.DSPy` | `defdsyp/2,3` | Move + add generation telemetry |
| `transform_*_result/1` | `DSPex.Bridge` | `SnakepitGrpcBridge.Schema.DSPy` | `transform_*_result/1` | Move + add transformation metrics |
| `init_bidirectional_session/1` | `DSPex.Bridge` | `SnakepitGrpcBridge.Bridge.Tools` | `init_bidirectional_session/1` | Move to tools module |
| `create_enhanced_wrapper/2` | `DSPex.Bridge` | `SnakepitGrpcBridge.Codegen.DSPy` | `create_enhanced_wrapper/2` | Move + add wrapper analytics |
| `execute_enhanced/3` | `DSPex.Bridge` | `SnakepitGrpcBridge.Cognitive.Worker` | `execute_enhanced/3` | Move to worker execution |
| `register_custom_tool/4` | `DSPex.Bridge` | `SnakepitGrpcBridge.Bridge.Tools` | `register_custom_tool/4` | Move to tools module |
| `list_elixir_tools/1` | `DSPex.Bridge` | `SnakepitGrpcBridge.Bridge.Tools` | `list_elixir_tools/1` | Move to tools module |

### Snakepit Bridge Modules → Cognitive Architecture

| Current Module | Size (Lines) | Target Module | Migration Type | Cognitive Enhancement |
|----------------|--------------|---------------|----------------|----------------------|
| `snakepit/bridge/session.ex` | 399 | `SnakepitGrpcBridge.Cognitive.Scheduler` | Refactor + Enhance | Add session routing intelligence |
| `snakepit/bridge/session_store.ex` | 1158 | `SnakepitGrpcBridge.Bridge.Context` | Move + Enhance | Add state persistence telemetry |
| `snakepit/bridge/tool_registry.ex` | 217 | `SnakepitGrpcBridge.Bridge.Tools` | Move + Enhance | Add tool usage analytics |
| `snakepit/bridge/serialization.ex` | 288 | `SnakepitGrpcBridge.Bridge.Serialization` | Move | Add serialization performance metrics |
| `snakepit/bridge/variables.ex` | 590 | `SnakepitGrpcBridge.Bridge.Variables` | Move + Enhance | Add variable usage telemetry |
| `snakepit/bridge/variables/*` | ~500 | `SnakepitGrpcBridge.Bridge.Variables.Types` | Move | Add type validation metrics |

### Snakepit gRPC Modules → Cognitive Architecture

| Current Module | Size (Lines) | Target Module | Migration Type | Cognitive Enhancement |
|----------------|--------------|---------------|----------------|----------------------|
| `snakepit/grpc/bridge_server.ex` | 902 | `SnakepitGrpcBridge.GRPC.Server` | Move + Enhance | Add request/response telemetry |
| `snakepit/grpc/client.ex` | 269 | `SnakepitGrpcBridge.GRPC.Client` | Move + Enhance | Add connection health monitoring |
| `snakepit/grpc/client_impl.ex` | 587 | `SnakepitGrpcBridge.GRPC.ClientImpl` | Move + Enhance | Add client performance metrics |
| `snakepit/grpc/snakepit.pb.ex` | 155 | `SnakepitGrpcBridge.GRPC.Proto` | Move | No changes needed |
| `snakepit/grpc/generated/*` | ~1000 | `SnakepitGrpcBridge.GRPC.Generated` | Move | No changes needed |

### Snakepit Core → Enhanced Infrastructure

| Current Module | Size (Lines) | Enhancement Type | Cognitive-Ready Features |
|----------------|--------------|------------------|-------------------------|
| `snakepit.ex` | 197 | Enhance | Add cognitive-ready adapter behavior, telemetry hooks |
| `snakepit/pool/pool.ex` | 609 | Enhance | Add worker performance tracking, session affinity telemetry |
| `snakepit/pool/registry.ex` | 89 | Enhance | Add worker health monitoring, specialization tracking |
| `snakepit/session_helpers.ex` | 133 | Enhance | Add session analytics, performance correlation |
| `snakepit/adapter.ex` | 120 | Enhance | Add cognitive capabilities metadata, performance callbacks |
| `snakepit/telemetry.ex` | 202 | Enhance | Expand for comprehensive cognitive data collection |

## Cognitive Module Structure

### SnakepitGrpcBridge.Cognitive.Worker

**Purpose**: Enhanced worker with cognitive-ready structure
**Current Sources**: 
- Worker logic from `snakepit/pool/pool.ex`
- gRPC worker from `snakepit/grpc_worker.ex`
- Execution logic from `DSPex.Bridge.execute_enhanced/3`

**Cognitive Enhancements**:
```elixir
defstruct [
  # Current functionality (implemented)
  :worker_id, :grpc_client, :session_store, :health_status,
  
  # Cognitive-ready infrastructure (telemetry now)
  :telemetry_collector, :performance_history, :task_metadata_cache,
  
  # Future cognitive capabilities (placeholders)
  :learning_state, :specialization_profile, :collaboration_network
]
```

### SnakepitGrpcBridge.Cognitive.Scheduler

**Purpose**: Enhanced scheduling with routing intelligence
**Current Sources**:
- Session routing from `snakepit/bridge/session.ex`
- Session helpers from `snakepit/session_helpers.ex`
- Pool worker selection from `snakepit/pool/pool.ex`

**Cognitive Enhancements**:
```elixir
defstruct [
  # Current scheduling state
  :session_affinity_map, :worker_availability, :routing_stats,
  
  # Cognitive-ready features (telemetry now)
  :routing_telemetry, :session_analytics, :performance_correlations,
  
  # Future cognitive capabilities (placeholders)
  :routing_ml_model, :intelligent_load_balancer, :predictive_scheduler
]
```

### SnakepitGrpcBridge.Cognitive.Evolution

**Purpose**: Implementation selection with learning capability
**Current Sources**:
- Current heuristics scattered throughout bridge modules
- Simple rule-based selection logic

**Cognitive Enhancements**:
```elixir
defstruct [
  # Current selection logic
  :implementation_strategies, :selection_history, :performance_data,
  
  # Cognitive-ready infrastructure (data collection now)
  :selection_telemetry, :outcome_tracking, :pattern_analysis,
  
  # Future cognitive capabilities (placeholders)  
  :evolution_algorithm, :performance_predictor, :ab_testing_engine
]
```

### SnakepitGrpcBridge.Schema.DSPy

**Purpose**: Enhanced schema discovery with optimization
**Current Sources**:
- `DSPex.Bridge.discover_schema/2`
- `DSPex.Bridge.call_dspy/5`
- `DSPex.Bridge.create_instance/3`

**Cognitive Enhancements**:
```elixir
# Add caching layer
@schema_cache :ets.new(:schema_cache, [:set, :public, :named_table])

# Add telemetry collection
def discover_schema(module_path, opts) do
  start_time = System.monotonic_time(:microsecond)
  result = perform_discovery(module_path, opts)
  duration = System.monotonic_time(:microsecond) - start_time
  
  # Collect telemetry for future optimization
  record_discovery_telemetry(module_path, result, duration)
  result
end
```

### SnakepitGrpcBridge.Codegen.DSPy

**Purpose**: Enhanced code generation with usage analytics
**Current Sources**:
- `DSPex.Bridge.defdsyp/2,3` macro
- Wrapper generation logic
- Enhanced wrapper creation

**Cognitive Enhancements**:
```elixir
defmacro defdsyp(module_name, class_path, config) do
  generation_id = generate_unique_id()
  
  # Record wrapper generation for future optimization
  quote do
    # Current wrapper generation logic
    # + 
    # Telemetry collection for usage patterns
    SnakepitGrpcBridge.Codegen.DSPy.record_wrapper_generation(
      unquote(module_name), unquote(class_path), unquote(config), unquote(generation_id)
    )
  end
end
```

## Implementation Priority Matrix

### Week 1 (Infrastructure + Core Modules)

| Priority | Module | Complexity | Dependencies | Completion Day |
|----------|--------|------------|--------------|----------------|
| 1 | Package Structure Creation | Low | None | Day 1 |
| 2 | Snakepit Core Extraction | Medium | Package Structure | Day 2 |
| 3 | SnakepitGrpcBridge.Cognitive.Worker | High | Core + gRPC modules | Day 4 |
| 4 | SnakepitGrpcBridge.Schema.DSPy | High | Worker + Bridge modules | Day 4 |
| 5 | SnakepitGrpcBridge.Codegen.DSPy | Medium | Schema modules | Day 4 |

### Week 2 (Integration + Testing)

| Priority | Module | Complexity | Dependencies | Completion Day |
|----------|--------|------------|--------------|----------------|
| 1 | DSPex Integration Updates | Medium | All bridge modules | Day 6-7 |
| 2 | SnakepitGrpcBridge.Cognitive.Scheduler | Medium | Worker + Session modules | Day 8 |
| 3 | SnakepitGrpcBridge.Cognitive.Evolution | Low | All cognitive modules | Day 8 |
| 4 | API Compatibility Validation | High | Complete integration | Day 8-9 |
| 5 | Performance Benchmarking | Medium | Working system | Day 9-10 |

### Week 3 (Polish + Documentation)

| Priority | Module | Complexity | Dependencies | Completion Day |
|----------|--------|------------|--------------|----------------|
| 1 | Comprehensive Testing | High | Complete system | Day 11-12 |
| 2 | Performance Optimization | Medium | Test results | Day 13-14 |
| 3 | Documentation Completion | Low | Stable system | Day 15 |
| 4 | Release Preparation | Low | All above | Day 15 |

## Dependency Resolution Strategy

### Phase 1: Clean Extraction
1. **Extract Core Infrastructure**: Remove all bridge-specific logic from Snakepit
2. **Create Bridge Package**: Set up SnakepitGrpcBridge with cognitive structure
3. **Establish Interfaces**: Define clear adapter behavior between packages

### Phase 2: Module Migration  
1. **Move Bridge Modules**: Transfer all bridge functionality to new package
2. **Update Namespaces**: Change all internal references to new module paths
3. **Implement Adapter**: Create Snakepit.Adapter implementation in bridge

### Phase 3: Integration Testing
1. **API Validation**: Ensure all DSPex APIs work identically
2. **Performance Testing**: Verify no significant performance regression
3. **Cognitive Readiness**: Validate telemetry collection and future extensibility

## Success Metrics

### Technical Metrics
- **Code Reduction**: Snakepit Core < 2000 lines (from ~7000 lines)
- **Functionality Preservation**: 100% API compatibility
- **Performance Impact**: < 5% latency increase
- **Test Coverage**: > 95% for both packages

### Architectural Metrics  
- **Separation Quality**: Zero domain logic in Snakepit Core
- **Cognitive Readiness**: Telemetry collection active in all modules
- **Future Extensibility**: Configuration-only cognitive feature activation
- **Documentation Quality**: Complete API and architecture documentation

This mapping provides the detailed blueprint for the 3-week implementation, ensuring systematic migration while building the cognitive-ready architecture foundation.