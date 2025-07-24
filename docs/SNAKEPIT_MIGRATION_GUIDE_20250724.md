# DSPex to Snakepit SessionStore Migration Guide - July 24, 2025

## Executive Summary

This guide outlines the migration from DSPex's custom state management layer to using Snakepit's `SessionStore` directly. The analysis shows this migration is not only feasible but recommended for architectural simplicity and maintainability.

## Current Architecture Analysis

### DSPex State Management Layer
DSPex currently implements a dual-backend state management system:

```
DSPex.Context
    ↓
DSPex.Bridge.StateProvider (behaviour)
    ↓
┌─────────────────┬─────────────────┐
│  LocalState     │  BridgedState   │
│  (Agent-based)  │  (SessionStore) │
└─────────────────┴─────────────────┘
```

**Files Involved:**
- `/lib/dspex/context.ex` - Main context GenServer
- `/lib/dspex/bridge/state_provider.ex` - Behaviour definition
- `/lib/dspex/bridge/state/local.ex` - Agent-based local storage
- `/lib/dspex/bridge/state/bridged.ex` - SessionStore adapter
- `/lib/dspex/bridge/state/bridged_error_handler.ex` - Error handling
- `/lib/dspex/bridge/state/bridged_metrics.ex` - Metrics collection

### Current BridgedState Implementation
The existing `BridgedState` is already a thin adapter that delegates to `Snakepit.Bridge.SessionStore`:

```elixir
def register_variable(state, name, type, initial_value, opts) do
  # Use SessionStore's register_variable API directly
  case SessionStore.register_variable(
         state.session_id,
         name,
         type,
         initial_value,
         opts
       ) do
    {:ok, var_id} -> {:ok, {var_id, state}}
    # ... error handling
  end
end
```

## Python Adapter Analysis

### Two gRPC Adapters Comparison

**`/priv/python/dspex_adapters/dspy_grpc.py` (921 lines):**
- **Enhanced functionality** with 16 @tool methods
- Includes bidirectional tool support (`register_elixir_tool`, `enhanced_predict`, `enhanced_chain_of_thought`)
- Universal DSPy function caller with introspection
- Schema discovery capabilities
- **More complete implementation**

**`/priv/python/snakepit_bridge/adapters/dspy_grpc.py` (723 lines):**
- **Basic functionality** with 10 @tool methods
- Standard DSPy operations
- Missing enhanced/bidirectional features
- **Simpler, more focused implementation**

**Recommendation:** Keep the `dspex_adapters/dspy_grpc.py` version as it provides the full feature set needed for DSPex.

### Helper Files Assessment

**`dspex_helper.py` (62 lines):**
- **Purpose:** Helper functions for Python-side DSPy configuration
- **Key functions:** `configure_dspy_with_stored_lm()`, `create_and_configure_lm()`
- **Status:** **Keep** - Contains useful DSPy configuration logic not in the main adapter

**`dspy_config.py` (62 lines):**
- **Purpose:** DSPy configuration utilities for different model types
- **Key functions:** `configure_lm()`, `get_current_lm()`, `create_module_with_lm()`
- **Status:** **Keep** - Provides reusable configuration functions

## Migration Strategy

### Phase 1: Remove DSPex State Management Layer

**Goal:** Eliminate the custom StateProvider abstraction and use Snakepit's SessionStore directly.

**Files to Remove:**
```
/lib/dspex/bridge/state_provider.ex
/lib/dspex/bridge/state/local.ex
/lib/dspex/bridge/state/bridged.ex
/lib/dspex/bridge/state/bridged_error_handler.ex
/lib/dspex/bridge/state/bridged_metrics.ex
```

**Files to Modify:**
```
/lib/dspex/context.ex - Update to use SessionStore directly
```

### Phase 2: Simplify Context Implementation

**Current Context Architecture:**
```elixir
defmodule DSPex.Context do
  # GenServer with backend switching logic
  # Automatic LocalState -> BridgedState migration
  # StateProvider behaviour abstraction
end
```

**Proposed Simplified Architecture:**
```elixir
defmodule DSPex.Context do
  # Thin wrapper around Snakepit.Bridge.SessionStore
  # Direct SessionStore API usage
  # Remove backend switching complexity
end
```

### Phase 3: Update API Calls

**Before (Current):**
```elixir
# Context manages backend selection
{:ok, ctx} = DSPex.Context.start_link()
DSPex.Variables.set(ctx, :temperature, 0.7)

# Automatic backend switching on Python usage
DSPex.Modules.ChainOfThought.new(ctx, "question -> answer")
```

**After (Simplified):**
```elixir
# Direct SessionStore usage
session_id = "my_session"
{:ok, _session} = Snakepit.Bridge.SessionStore.create_session(session_id)

# Direct SessionStore variable operations
{:ok, var_id} = Snakepit.Bridge.SessionStore.register_variable(
  session_id, :temperature, :float, 0.7
)

# DSPy modules use same session_id
{:ok, module_ref} = DSPex.Modules.ChainOfThought.new(session_id, "question -> answer")
```

## Snakepit SessionStore Extensibility Analysis

### Current SessionStore Capabilities

**Core Features:**
- ETS-based session storage with TTL
- Variable registration with type system
- Batch operations support
- Program storage (global and session-scoped)
- Automatic cleanup and monitoring

**Architecture:**
```elixir
defmodule Snakepit.Bridge.SessionStore do
  use GenServer
  # Centralized ETS management
  # TTL-based expiration
  # Variables API with Snakepit.Bridge.Variables.Types
end
```

### Extension Points in Snakepit

**1. Type System Extension:**
```elixir
# Snakepit.Bridge.Variables.Types is designed to be extensible
defmodule MyApp.CustomTypes do
  @behaviour Snakepit.Bridge.Variables.TypeModule
  
  def validate(value), do: {:ok, transformed_value}
  def validate_constraints(value, constraints), do: :ok
end
```

**2. SessionStore is Public API:**
- All functions are public and documented
- Designed for direct consumption by client applications
- No indication it's internal-only to Snakepit

**3. No DSPex-Specific Extensions Needed:**
The SessionStore API already provides everything DSPex needs:
- Variable management with type safety
- Session lifecycle management
- Program storage
- Cross-process state sharing

### Should DSPex Extend SessionStore?

**Analysis:** **No extension needed**

**Rationale:**
1. **Complete API:** SessionStore provides all required functionality
2. **Type System:** Already extensible for custom types
3. **Session Management:** Built-in TTL, cleanup, monitoring
4. **Performance:** Optimized ETS implementation
5. **Maintenance:** Let Snakepit team maintain state management

**Recommendation:** Use SessionStore as-is. If specific DSPy-related functionality is needed, implement it as DSPex utilities that use SessionStore, not as extensions to SessionStore itself.

## Implementation Roadmap

### Immediate Actions (Low Risk)
1. **Remove unused adapter:** Already completed
2. **Keep enhanced gRPC adapter:** `/priv/python/dspex_adapters/dspy_grpc.py`
3. **Keep helper files:** `dspex_helper.py` and `dspy_config.py` provide value

### Short-term Migration (Medium Risk)
1. **Update Context module** to use SessionStore directly
2. **Remove StateProvider abstraction layer**
3. **Update all DSPex modules** to work with session_id instead of context pid
4. **Update examples and documentation**

### Long-term Benefits
1. **Simplified architecture** - Remove abstraction layer
2. **Better performance** - Direct SessionStore calls
3. **Easier maintenance** - One less layer to debug
4. **Consistent with Snakepit** - Use proven infrastructure

## Risk Assessment

### Low Risk Changes
- Remove StateProvider abstraction (well-defined interface)
- Update Context to use SessionStore directly (thin wrapper exists)
- Keep enhanced Python adapter (more features = safer)

### Medium Risk Changes
- Update all DSPex module APIs (breaking changes to public API)
- Change from GenServer context to session_id pattern
- Update examples and documentation

### Migration Safety
The current `BridgedState` already delegates everything to SessionStore, so the migration is essentially removing a pass-through layer rather than changing functionality.

## Conclusion

**Feasibility:** ✅ **Highly Feasible**
- Current BridgedState is already a thin SessionStore wrapper
- SessionStore provides complete functionality
- Well-defined interfaces make migration straightforward

**Extensibility:** ✅ **No Extension Needed**
- SessionStore API is complete for DSPex needs
- Type system is already extensible
- Better to consume than extend

**Recommendation:** ✅ **Proceed with Migration**
- Remove DSPex state management layer
- Use Snakepit SessionStore directly
- Focus DSPex on DSPy-specific logic
- Maintain helper utilities for DSPy configuration

This migration will simplify DSPex architecture while leveraging Snakepit's proven state management infrastructure.