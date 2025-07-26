# DSPex Bridge Migration Mapping

## Overview

This document provides a detailed file-by-file mapping for migrating DSPex bridge functionality to the new cognitive-ready architecture in SnakepitGrpcBridge.

**Current State**: DSPex still contains bridge functionality that directly calls Snakepit
**Target State**: DSPex uses SnakepitGrpcBridge with cognitive-ready modules

## DSPex File Migration Map

### 1. `lib/dspex/bridge.ex` (493 lines)

**Current Functions**:
- `defdsyp/2,3` - Macro for DSPy wrapper generation
- Uses `Snakepit.execute_in_session` directly
- Contains enhanced_predict and enhanced_chain_of_thought logic
- Tool registration via `DSPex.Bridge.Tools`

**Migration Target**: 
- **Primary**: `SnakepitGrpcBridge.Codegen.DSPy` 
- **Secondary**: `SnakepitGrpcBridge.Schema.DSPy` for call_dspy functions

**Migration Strategy**:
1. Move `defdsyp` macro to `SnakepitGrpcBridge.Codegen.DSPy`
2. Replace `Snakepit.execute_in_session` with `SnakepitGrpcBridge.execute_dspy`
3. Add telemetry collection for wrapper generation
4. Add usage analytics for future AI optimization

**Code Changes Required**:
```elixir
# Old (DSPex.Bridge)
Snakepit.execute_in_session(session_id, "call_dspy", %{...})

# New (DSPex.Bridge using SnakepitGrpcBridge)
SnakepitGrpcBridge.execute_dspy(session_id, "call_dspy_bridge", %{...})
```

### 2. `lib/dspex/bridge/tools.ex` (340 lines)

**Current Functions**:
- `register_standard_tools/1` - Registers common Elixir tools
- `register_tool/4` - Individual tool registration
- Tool execution logic

**Migration Target**: `SnakepitGrpcBridge.Bridge.Tools`

**Migration Strategy**:
1. Move all tool registration logic to bridge package
2. Enhance with tool usage analytics
3. Add cognitive-ready hooks for tool selection optimization

**Code Changes Required**:
```elixir
# Old (DSPex.Bridge.Tools)
def register_standard_tools(session_id) do
  Snakepit.execute_in_session(session_id, "register_elixir_tool", %{...})
end

# New (DSPex.Bridge.Tools using SnakepitGrpcBridge)
def register_standard_tools(session_id) do
  SnakepitGrpcBridge.register_elixir_tool(session_id, name, function, metadata)
end
```

### 3. `lib/dspex/variables.ex` (591 lines)

**Current Functions**:
- High-level variable API
- References to Snakepit.Bridge.SessionStore
- Variable type definitions and validation

**Migration Target**: Keep in DSPex but update to use SnakepitGrpcBridge

**Migration Strategy**:
1. Keep API in DSPex for backward compatibility
2. Replace all Snakepit.Bridge.SessionStore calls with SnakepitGrpcBridge.Bridge.Variables
3. Add telemetry for variable usage patterns

**Code Changes Required**:
```elixir
# Old (DSPex.Variables)
def set(context, name, value, opts \\ []) do
  session_id = get_session_id(context)
  result = Snakepit.Bridge.SessionStore.set_variable(session_id, name, value, type, constraints)
  # ...
end

# New (DSPex.Variables using SnakepitGrpcBridge)
def set(context, name, value, opts \\ []) do
  session_id = get_session_id(context)
  result = SnakepitGrpcBridge.set_variable(session_id, name, value, opts)
  # ...
end
```

### 4. `lib/dspex/context.ex` (394 lines)

**Current Functions**:
- Central execution context
- Direct use of Snakepit.Bridge.SessionStore
- Session management

**Migration Target**: Keep in DSPex but update to use SnakepitGrpcBridge

**Migration Strategy**:
1. Keep Context in DSPex as user-facing API
2. Replace SessionStore references with SnakepitGrpcBridge calls
3. Add context telemetry for usage patterns

**Code Changes Required**:
```elixir
# Old (DSPex.Context)
def init(opts) do
  session_id = opts[:session_id] || generate_session_id()
  
  case SessionStore.create_session(session_id) do
    {:ok, _session} -> ...
  end
end

# New (DSPex.Context using SnakepitGrpcBridge)  
def init(opts) do
  session_id = opts[:session_id] || generate_session_id()
  
  case SnakepitGrpcBridge.initialize_session(session_id, opts) do
    {:ok, _session_info} -> ...
  end
end
```

### 5. `lib/dspex/context/monitor.ex` (232 lines)

**Current Functions**:
- Session monitoring
- Health checks
- Cleanup coordination

**Migration Target**: Keep in DSPex but update to use SnakepitGrpcBridge

**Migration Strategy**:
1. Update to use SnakepitGrpcBridge health check APIs
2. Add monitoring telemetry

## Summary of DSPex Changes

### Files to Modify (not move):
1. `lib/dspex/bridge.ex` - Update to use SnakepitGrpcBridge APIs
2. `lib/dspex/bridge/tools.ex` - Update to use SnakepitGrpcBridge.Bridge.Tools
3. `lib/dspex/variables.ex` - Update to use SnakepitGrpcBridge.Bridge.Variables
4. `lib/dspex/context.ex` - Update to use SnakepitGrpcBridge session APIs
5. `lib/dspex/context/monitor.ex` - Update monitoring calls

### Dependency Changes:
```elixir
# mix.exs
def deps do
  [
    # Add:
    {:snakepit_grpc_bridge, "~> 0.1"},
    # Keep other deps, remove direct :snakepit dependency if separate
  ]
end
```

### Configuration Changes:
```elixir
# config/config.exs
# Remove any direct Snakepit adapter configuration
# SnakepitGrpcBridge will auto-configure Snakepit

config :snakepit_grpc_bridge,
  python_executable: "python3",
  grpc_port: 0,
  cognitive_features: %{
    telemetry_collection: true,
    performance_monitoring: true
  }
```

## Migration Order

1. **Phase 1**: Update mix.exs dependencies
2. **Phase 2**: Update configuration
3. **Phase 3**: Update Context and Variables to use new APIs
4. **Phase 4**: Update Bridge to use new execution APIs
5. **Phase 5**: Update Tools to use new registration APIs
6. **Phase 6**: Run tests and fix any issues

## Backwards Compatibility

All DSPex public APIs remain unchanged. Users of DSPex will not need to change their code. The changes are internal implementation details only.

## Performance Considerations

- Initial performance should be identical
- Telemetry collection adds minimal overhead (<1%)
- Caching in SnakepitGrpcBridge should improve performance
- Future cognitive features can be enabled without code changes