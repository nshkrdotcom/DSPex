# Snakepit Bridge Migration Mapping

## Overview

This document provides a detailed file-by-file mapping for migrating all bridge, gRPC, and variable functionality from Snakepit to SnakepitGrpcBridge, leaving Snakepit as pure infrastructure.

**Current State**: Snakepit v0.4.0 contains bridge, gRPC, variables, and infrastructure
**Target State**: 
- Snakepit Core: Pure infrastructure only (pool, sessions, adapters)
- SnakepitGrpcBridge: All bridge functionality in cognitive-ready architecture

## Snakepit File Migration Map

### Bridge Module Migrations

#### 1. `lib/snakepit/bridge/session_store.ex` (1158 lines)

**Current Location**: `snakepit/previous/lib/snakepit/bridge/session_store.ex`
**Target Location**: `SnakepitGrpcBridge.Bridge.SessionStore`

**Key Functions**:
- Session CRUD operations
- Variable storage within sessions
- TTL-based expiration
- ETS table management

**Cognitive Enhancements**:
- Add session usage telemetry
- Track session patterns for learning
- Performance monitoring per session

#### 2. `lib/snakepit/bridge/variables.ex` (590 lines)

**Current Location**: `snakepit/previous/lib/snakepit/bridge/variables.ex`
**Target Location**: `SnakepitGrpcBridge.Bridge.Variables`

**Key Functions**:
- Variable type system
- Validation logic
- High-level variable API

**Cognitive Enhancements**:
- Variable usage analytics
- Type usage patterns
- Validation performance metrics

#### 3. `lib/snakepit/bridge/variables/types/*.ex` (~500 lines total)

**Current Files**:
- `types.ex` - Type registry
- `types/boolean.ex`
- `types/choice.ex`
- `types/embedding.ex`
- `types/float.ex`
- `types/integer.ex`
- `types/module.ex`
- `types/string.ex`
- `types/tensor.ex`

**Target Location**: `SnakepitGrpcBridge.Bridge.Variables.Types.*`

**Migration**: Direct move with telemetry additions

#### 4. `lib/snakepit/bridge/tool_registry.ex` (217 lines)

**Current Location**: `snakepit/previous/lib/snakepit/bridge/tool_registry.ex`
**Target Location**: `SnakepitGrpcBridge.Bridge.ToolRegistry`

**Key Functions**:
- Tool registration (Elixir & Python)
- Tool discovery
- Execution dispatch

**Cognitive Enhancements**:
- Tool usage frequency tracking
- Performance per tool metrics
- Tool recommendation engine prep

#### 5. `lib/snakepit/bridge/serialization.ex` (288 lines)

**Current Location**: `snakepit/previous/lib/snakepit/bridge/serialization.ex`
**Target Location**: `SnakepitGrpcBridge.Bridge.Serialization`

**Key Functions**:
- MessagePack serialization
- Type conversion
- Binary protocol handling

**Cognitive Enhancements**:
- Serialization performance metrics
- Type conversion patterns

#### 6. `lib/snakepit/bridge/session.ex` (399 lines)

**Current Location**: `snakepit/previous/lib/snakepit/bridge/session.ex`
**Target Location**: Merge into `SnakepitGrpcBridge.Cognitive.Scheduler`

**Key Functions**:
- Session struct definition
- Session lifecycle management

**Cognitive Integration**:
- Becomes part of intelligent scheduling
- Session affinity learning

### gRPC Module Migrations

#### 7. `lib/snakepit/grpc/bridge_server.ex` (902 lines)

**Current Location**: `snakepit/previous/lib/snakepit/grpc/bridge_server.ex`
**Target Location**: `SnakepitGrpcBridge.GRPC.Server`

**Key Functions**:
- gRPC service implementation
- Request/response handling
- Protocol implementation

**Cognitive Enhancements**:
- Request pattern analysis
- Response time optimization
- Error pattern learning

#### 8. `lib/snakepit/grpc/client.ex` (269 lines)

**Current Location**: `snakepit/previous/lib/snakepit/grpc/client.ex`
**Target Location**: `SnakepitGrpcBridge.GRPC.Client`

**Key Functions**:
- gRPC client connection
- Channel management

**Cognitive Enhancements**:
- Connection health monitoring
- Retry pattern optimization

#### 9. `lib/snakepit/grpc/client_impl.ex` (587 lines)

**Current Location**: `snakepit/previous/lib/snakepit/grpc/client_impl.ex`
**Target Location**: `SnakepitGrpcBridge.GRPC.ClientImpl`

**Key Functions**:
- Client implementation details
- Request execution
- Response handling

**Cognitive Enhancements**:
- Request optimization
- Response caching intelligence

#### 10. `lib/snakepit/grpc/*.pb.ex` (Protocol Buffer files)

**Current Files**:
- `snakepit.pb.ex`
- `snakepit_bridge.pb.ex`
- `generated/snakepit_bridge.pb.ex`

**Target Location**: `SnakepitGrpcBridge.GRPC.Proto.*`

**Migration**: Direct move, no changes needed

### Worker and Adapter Migrations

#### 11. `lib/snakepit/grpc_worker.ex` (613 lines)

**Current Location**: `snakepit/previous/lib/snakepit/grpc_worker.ex`
**Target Location**: `SnakepitGrpcBridge.Cognitive.Worker`

**Key Functions**:
- Worker process management
- gRPC execution
- Health monitoring

**Cognitive Transformation**:
- Enhanced with learning capabilities
- Performance history tracking
- Task specialization prep

#### 12. `lib/snakepit/adapters/grpc_bridge.ex` (94 lines)

**Current Location**: `snakepit/previous/lib/snakepit/adapters/grpc_bridge.ex`
**Target Location**: Merge into `SnakepitGrpcBridge.Adapter`

**Migration**: Functionality merged into main adapter

#### 13. `lib/snakepit/adapters/grpc_python.ex` (287 lines)

**Current Location**: `snakepit/previous/lib/snakepit/adapters/grpc_python.ex`
**Target Location**: Merge into `SnakepitGrpcBridge.Adapter`

**Migration**: Python-specific logic integrated into unified adapter

#### 14. `lib/snakepit/python.ex` (528 lines)

**Current Location**: `snakepit/previous/lib/snakepit/python.ex`
**Target Location**: `SnakepitGrpcBridge.Python.Bridge`

**Key Functions**:
- Python process management
- Bridge script execution

## Files Remaining in Snakepit Core

These files stay in Snakepit as pure infrastructure:

1. `lib/snakepit.ex` - Main API (enhanced with adapter behavior)
2. `lib/snakepit/adapter.ex` - Adapter behavior definition
3. `lib/snakepit/application.ex` - OTP application
4. `lib/snakepit/pool/*` - All pooling infrastructure
5. `lib/snakepit/session_helpers.ex` - Basic session utilities
6. `lib/snakepit/telemetry.ex` - Core telemetry
7. `lib/snakepit/utils.ex` - Basic utilities

## Migration Summary

### Total Files to Migrate: 25+ files
### Total Lines to Migrate: ~7,000 lines
### Files Remaining in Core: 10 files (~1,500 lines)

## Dependency Updates

### Snakepit Core mix.exs:
```elixir
defp deps do
  [
    # Remove all gRPC dependencies
    # Remove protobuf dependencies
    # Keep only core OTP dependencies
    {:telemetry, "~> 1.0"},
    {:typed_struct, "~> 0.3"}
  ]
end
```

### SnakepitGrpcBridge mix.exs:
```elixir
defp deps do
  [
    {:snakepit, "~> 0.5"}, # New core-only version
    {:grpc, "~> 0.5"},
    {:protobuf, "~> 0.10"},
    {:jason, "~> 1.3"},
    {:msgpax, "~> 2.3"},
    {:telemetry, "~> 1.0"}
  ]
end
```

## Test Migration

### Tests to Move:
- All `test/snakepit/bridge/*` tests → `snakepit_grpc_bridge/test/bridge/*`
- All `test/snakepit/grpc/*` tests → `snakepit_grpc_bridge/test/grpc/*`
- All integration tests → `snakepit_grpc_bridge/test/integration/*`

### Tests to Keep:
- Pool tests remain in Snakepit
- Basic adapter tests remain in Snakepit

## Python Assets Migration

### Move to SnakepitGrpcBridge:
- `priv/python/*` - All Python bridge scripts
- `grpc/*.proto` - Protocol definitions

## Configuration Changes

### Snakepit Core config:
```elixir
config :snakepit,
  # Only infrastructure config
  pool_size: 4,
  session_cleanup_interval: 300_000
```

### SnakepitGrpcBridge config:
```elixir
config :snakepit_grpc_bridge,
  # All bridge-specific config
  python_executable: "python3",
  grpc_port: 0,
  message_pack_enabled: true,
  cognitive_features: %{
    telemetry_collection: true
  }
```

## Migration Phases

### Phase 1: Package Setup
1. Finalize SnakepitGrpcBridge package structure
2. Set up dependencies
3. Configure build system

### Phase 2: Core Extraction
1. Remove bridge modules from Snakepit
2. Update Snakepit to pure infrastructure
3. Enhance adapter behavior

### Phase 3: Module Migration
1. Move bridge modules with cognitive enhancements
2. Move gRPC modules with telemetry
3. Move worker logic to cognitive worker

### Phase 4: Integration
1. Implement SnakepitGrpcBridge.Adapter
2. Update all internal references
3. Test adapter integration

### Phase 5: Testing
1. Migrate relevant tests
2. Add new cognitive readiness tests
3. Performance validation

## Expected Outcomes

1. **Snakepit Core**: Clean, focused infrastructure package
2. **SnakepitGrpcBridge**: Feature-complete bridge with cognitive readiness
3. **Zero Breaking Changes**: Existing code continues to work
4. **Performance**: Same or better due to optimizations
5. **Future Ready**: Easy path to cognitive enhancements