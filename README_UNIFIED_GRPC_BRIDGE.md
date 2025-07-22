# DSPex Unified gRPC Bridge

This document describes the DSPex side of the unified gRPC bridge implementation, focusing on the Context API and dual backend architecture.

## Overview

DSPex provides a high-level Context API that abstracts away the complexity of state management. It automatically switches between a fast pure-Elixir backend and a Python-integrated backend based on your needs.

## Implementation Status

### Stage 0: Protocol Foundation ✅
- gRPC client integration via Snakepit
- Protocol buffer support
- Basic connectivity established

### Stage 1: Core Variables ✅ 
- Variable registration and management
- Type system with validation
- Batch operations support

### Stage 2: DSPex Integration ✅
- `DSPex.Context` API implementation
- Dual backend architecture (LocalState/BridgedState)
- Automatic backend switching
- State migration support

## Architecture

```elixir
# User-facing API
DSPex.Context
    ├── LocalState (Pure Elixir - microsecond ops)
    └── BridgedState (gRPC - millisecond ops)
            └── SessionStore (Snakepit)
                    └── Python DSPy
```

## Quick Start

```elixir
# Start a context (automatically selects backend)
{:ok, ctx} = DSPex.Context.new()

# Register variables
{:ok, ctx} = DSPex.Context.put(ctx, :temperature, 0.7, type: :float)
{:ok, ctx} = DSPex.Context.put(ctx, :max_tokens, 100, type: :integer)

# Get values
{:ok, temp} = DSPex.Context.get(ctx, :temperature)

# Update values  
{:ok, ctx} = DSPex.Context.update(ctx, :temperature, 0.9)

# The context automatically switches to BridgedState when needed
# (e.g., when Python tools are registered)
```

## Backend Selection

DSPex automatically selects the appropriate backend:

1. **LocalState** (default):
   - Pure Elixir implementation
   - Microsecond latency
   - No external dependencies
   - Perfect for development and testing

2. **BridgedState** (automatic upgrade):
   - Activated when Python features are needed
   - Millisecond latency (gRPC overhead)
   - Full Python DSPy integration
   - Seamless state migration

## State Provider Behavior

Both backends implement the `StateProvider` behavior:

```elixir
@callback init(opts :: keyword()) :: {:ok, state} | {:error, reason}
@callback register_variable(state, name, type, value, opts) :: {:ok, {id, state}} | {:error, reason}
@callback get_variable(state, identifier) :: {:ok, value} | {:error, reason}
@callback set_variable(state, identifier, value, metadata) :: {:ok, state} | {:error, reason}
@callback list_variables(state) :: {:ok, [variable]} | {:error, reason}
# ... and more
```

## Type System

Supported types with validation and constraints:

- `:float` - With special values (`:infinity`, `:nan`)
- `:integer` - With min/max constraints
- `:string` - With length and pattern constraints
- `:boolean` - With flexible parsing

Example with constraints:
```elixir
{:ok, ctx} = DSPex.Context.put(ctx, :score, 0.5,
  type: :float,
  constraints: %{min: 0.0, max: 1.0}
)
```

## Testing

### Test Modes

```bash
# Fast unit tests (mock adapter)
mix test

# Protocol tests (bridge mock)
TEST_MODE=bridge_mock mix test

# Full integration (real Python)
TEST_MODE=full_integration mix test
```

### Expected Warnings

Some tests intentionally trigger warnings to verify error handling:
```
[warning] BridgedState: Failed to register variable good_var: {:unknown_type, :invalid_type}
[error] BridgedState: Failed to import 1 variables
```

These are captured and verified in the test suite - they indicate proper error handling.

## Performance

- **LocalState**: ~1-10 microseconds per operation
- **BridgedState**: ~1-5 milliseconds per operation
- **Batch operations**: Significantly faster for multiple operations
- **State migration**: One-time cost when switching backends

## Recent Updates (Stage 2 Compliance)

1. **Type System Deduplication**: LocalState now uses the centralized type system from Snakepit
2. **BridgedState Refactoring**: Now delegates directly to SessionStore API
3. **Test Improvements**: Proper log capture for expected warnings
4. **Serialization Fixes**: Resolved double-encoding issues

## Future Enhancements

- Streaming support for real-time updates
- Advanced caching strategies
- Performance optimizations
- Property-based testing

## Related Documentation

- [Snakepit Bridge Documentation](snakepit/README_UNIFIED_GRPC_BRIDGE.md)
- [Testing Guide](README_TESTING.md)
- [Protocol Specifications](docs/specs/unified_grpc_bridge/)
- [Implementation Status](docs/specs/unified_grpc_bridge/implementation_plan_stage2_compliance.md)