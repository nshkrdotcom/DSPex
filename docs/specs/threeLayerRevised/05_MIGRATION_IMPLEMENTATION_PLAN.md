# Migration Implementation Plan

## Overview

This document provides a detailed, step-by-step implementation plan for migrating from the current monolithic structure to the **Light Snakepit + Heavy Bridge** architecture.

## Migration Strategy

### Phase-Based Approach
1. **Phase 1**: Extract and Simplify Snakepit (1-2 weeks)
2. **Phase 2**: Create Heavy ML Platform (2-3 weeks)  
3. **Phase 3**: Simplify DSPex Consumer Layer (1 week)
4. **Phase 4**: Integration and Testing (1 week)
5. **Phase 5**: Documentation and Release (1 week)

**Total Timeline**: 6-8 weeks

## Detailed Implementation Plan

### Phase 1: Extract and Simplify Snakepit (1-2 weeks)

#### Week 1: Infrastructure Extraction

**Day 1-2: Create New Snakepit Package**
```bash
# Create new snakepit package
mkdir ../snakepit
cd ../snakepit
mix new . --app snakepit

# Set up basic structure
mkdir -p lib/snakepit/{pool,grpc,session}
mkdir -p priv/proto
```

**Day 3-4: Extract Core Infrastructure**
- Move generic pool management from current snakepit
- Remove all ML-specific code
- Create clean adapter behavior
- Extract session management utilities

**Files to Extract and Clean:**
```
FROM snakepit/lib/snakepit/pool/
TO   ../snakepit/lib/snakepit/pool/
- pool.ex (remove DSPy-specific logic)
- registry.ex (generic worker registry)
- supervisor.ex (generic supervision)

FROM snakepit/lib/snakepit/
TO   ../snakepit/lib/snakepit/
- session_helpers.ex -> session/manager.ex (remove ML logic)
```

**Day 5: Create Generic gRPC Infrastructure**
- Design generic gRPC protocol for any external process
- Create gRPC server that routes to adapters
- Create gRPC client utilities

**Files to Create:**
```
../snakepit/lib/snakepit/grpc/
├── server.ex          # Generic gRPC server
├── client.ex          # Generic gRPC client  
├── endpoint.ex        # Endpoint management
└── protocols.ex       # Protocol definitions

../snakepit/priv/proto/
└── snakepit.proto     # Basic gRPC protocol
```

#### Week 2: Infrastructure Completion

**Day 6-7: Adapter Pattern Implementation**
```elixir
# lib/snakepit/adapter.ex
defmodule Snakepit.Adapter do
  @callback execute(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback init(keyword()) :: {:ok, term()} | {:error, term()}
  @callback start_worker(term(), term()) :: {:ok, pid()} | {:error, term()}
end
```

**Day 8-9: Testing and Validation**
- Create comprehensive tests for infrastructure
- Validate that infrastructure is truly generic
- Test with mock adapter

**Day 10: Documentation**
- Document adapter behavior
- Create infrastructure usage examples
- Write integration guide

### Phase 2: Create Heavy ML Platform (2-3 weeks)

#### Week 3: Platform Foundation

**Day 11-12: Create SnakepitGRPCBridge Package**
```bash
# Create new snakepit_grpc_bridge package
mkdir ../snakepit_grpc_bridge
cd ../snakepit_grpc_bridge
mix new . --app snakepit_grpc_bridge

# Set up ML platform structure
mkdir -p lib/snakepit_grpc_bridge/{api,variables,tools,dspy,grpc,python}
mkdir -p priv/{proto,python/snakepit_bridge}
```

**Day 13-14: Move Python Code**
```bash
# Move ALL Python code to bridge
mv dspex/priv/python/* ../snakepit_grpc_bridge/priv/python/
mv snakepit/priv/python/* ../snakepit_grpc_bridge/priv/python/

# Reorganize Python structure
# FROM: Scattered Python files
# TO: ../snakepit_grpc_bridge/priv/python/snakepit_bridge/
#     ├── core/         # Core bridge functionality
#     ├── variables/    # Python variable management  
#     ├── tools/        # Python tool execution
#     └── dspy/         # Python DSPy integration
```

**Day 15: Create Snakepit Adapter**
```elixir
# lib/snakepit_grpc_bridge/adapter.ex
defmodule SnakepitGRPCBridge.Adapter do
  @behaviour Snakepit.Adapter
  
  def execute(command, args, opts) do
    # Route ML commands to appropriate modules
  end
end
```

#### Week 4: Core Systems Migration

**Day 16-17: Variables System**
```bash
# Move variable logic from DSPex
# FROM: dspex/lib/dspex/variables/
# TO:   ../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/variables/

# Create clean API
# lib/snakepit_grpc_bridge/api/variables.ex
```

**Files to Migrate:**
```
Variables System:
├── variables/manager.ex       # Variable lifecycle management
├── variables/types.ex         # ML data types and serialization  
├── variables/storage.ex       # Variable storage backend
├── variables/registry.ex      # Variable registry and discovery
└── variables/ml_types/        # Specialized ML type handlers
    ├── tensor.ex              # Tensor variable type
    ├── embedding.ex           # Embedding variable type
    └── model.ex               # Model variable type
```

**Day 18-19: Tools System**
```bash
# Move tool bridge logic
# FROM: dspex/lib/dspex/tools/ + snakepit bridge tools
# TO:   ../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/tools/
```

**Files to Migrate:**
```
Tools System:
├── tools/registry.ex         # Tool registration and discovery
├── tools/executor.ex         # Tool execution engine
├── tools/bridge.ex           # Python ↔ Elixir bridge
├── tools/serialization.ex    # Tool argument serialization
└── tools/validation.ex       # Tool validation and type checking
```

**Day 20: DSPy System Migration**
```bash
# Move DSPy integration
# FROM: dspex/lib/dspex/bridge.ex + snakepit DSPy code
# TO:   ../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/dspy/
```

#### Week 5: Platform Completion

**Day 21-22: Create Clean APIs**
```elixir
# lib/snakepit_grpc_bridge/api/variables.ex
defmodule SnakepitGRPCBridge.API.Variables do
  def create(session_id, name, type, value, opts \\ [])
  def get(session_id, identifier, default \\ nil)
  def set(session_id, identifier, value, opts \\ [])
  def list(session_id)
end

# lib/snakepit_grpc_bridge/api/tools.ex  
defmodule SnakepitGRPCBridge.API.Tools do
  def register_elixir_function(session_id, name, function, opts \\ [])
  def call(session_id, tool_name, parameters)
  def list(session_id)
end

# lib/snakepit_grpc_bridge/api/dspy.ex
defmodule SnakepitGRPCBridge.API.DSPy do
  def enhanced_predict(session_id, signature, inputs, opts \\ [])
  def enhanced_chain_of_thought(session_id, signature, inputs, opts \\ [])
  def discover_schema(module_path, opts \\ [])
end
```

**Day 23-24: Integration and Configuration**
```elixir
# mix.exs - Add snakepit dependency
defp deps do
  [
    {:snakepit, "~> 0.1.0"},
    # ... other deps
  ]
end

# config/config.exs - Configure snakepit to use our adapter
config :snakepit,
  adapter_module: SnakepitGRPCBridge.Adapter
```

**Day 25: Platform Testing**
- Test all migrated functionality
- Validate APIs work correctly
- Test Python bridge integration

### Phase 3: Simplify DSPex Consumer Layer (1 week)

#### Week 6: Consumer Layer Simplification

**Day 26-27: Update DSPex Dependencies**
```elixir
# dspex/mix.exs - Change to depend on bridge
defp deps do
  [
    {:snakepit_grpc_bridge, "~> 0.1.0"},  # Changed from snakepit
    # Remove Python-related dependencies
  ]
end
```

**Day 28-29: Simplify DSPex Code**
```bash
# Remove all implementation from DSPex
rm -rf dspex/lib/dspex/variables/
rm -rf dspex/lib/dspex/tools/  
rm -rf dspex/priv/python/

# Keep only orchestration
# dspex/lib/dspex/
# ├── bridge.ex      # defdsyp macro only
# └── api.ex         # High-level convenience functions
```

**Day 30: Update DSPex Implementation**
```elixir
# lib/dspex.ex - Update to use bridge APIs
defmodule DSPex do
  def predict(signature, inputs, opts \\ []) do
    with_auto_session(fn session_id ->
      SnakepitGRPCBridge.API.DSPy.enhanced_predict(session_id, signature, inputs, opts)
    end)
  end
  
  def set_variable(name, value) do
    with_global_session(fn session_id ->
      SnakepitGRPCBridge.API.Variables.set(session_id, name, value)
    end)
  end
end
```

**Day 31-32: Update defdsyp Macro**
```elixir
# lib/dspex/bridge.ex - Update macro to use bridge APIs
defmacro defdsyp(module_name, class_path, config \\ %{}) do
  quote do
    def create(opts \\ []) do
      session_id = opts[:session_id] || DSPex.Sessions.generate_temp_session_id()
      SnakepitGRPCBridge.API.DSPy.call(session_id, @class_path, "__init__", %{}, opts)
    end
    
    def execute({session_id, instance_id}, inputs, opts \\ []) do
      SnakepitGRPCBridge.API.DSPy.enhanced_predict(session_id, @signature, inputs, opts)
    end
  end
end
```

### Phase 4: Integration and Testing (1 week)

#### Week 7: System Integration

**Day 33-34: End-to-End Integration**
- Test complete pipeline: DSPex → SnakepitGRPCBridge → Snakepit
- Validate all functionality works as before
- Test performance characteristics

**Day 35-36: Comprehensive Testing**
```bash
# Test matrix:
# - All DSPex public APIs
# - All variable operations  
# - All tool operations
# - All DSPy integrations
# - Session management
# - Error handling
# - Performance benchmarks
```

**Day 37-38: Bug Fixes and Polish**
- Fix integration issues discovered in testing
- Polish APIs based on testing feedback
- Optimize performance bottlenecks

**Day 39: Release Preparation**
- Finalize version numbers
- Update all package metadata
- Prepare release notes

### Phase 5: Documentation and Release (1 week)

#### Week 8: Documentation and Release

**Day 40-41: Documentation**
- Update all README files
- Create migration guide for users
- Document new architecture
- Create examples and tutorials

**Day 42-43: Package Publishing**
```bash
# Publish in order (respecting dependencies):
cd ../snakepit && mix hex.publish
cd ../snakepit_grpc_bridge && mix hex.publish  
cd dspex && mix hex.publish
```

**Day 44-45: User Migration Support**
- Monitor for issues
- Provide migration support
- Update documentation based on feedback

**Day 46: Release Completion**
- Announce new architecture
- Celebrate clean separation! 🎉

## File Migration Matrix

### From Current Snakepit → New Snakepit
```
EXTRACT (Pure Infrastructure):
snakepit/lib/snakepit/pool/pool.ex → ../snakepit/lib/snakepit/pool/pool.ex (remove ML logic)
snakepit/lib/snakepit/session_helpers.ex → ../snakepit/lib/snakepit/session/manager.ex (remove ML logic)

CREATE (New Infrastructure):
../snakepit/lib/snakepit/adapter.ex (new adapter behavior)
../snakepit/lib/snakepit/grpc/server.ex (generic gRPC server)
../snakepit/lib/snakepit/grpc/client.ex (generic gRPC client)
```

### From Current Code → SnakepitGRPCBridge
```
MOVE (All ML Logic):
dspex/lib/dspex/variables/ → ../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/variables/
dspex/lib/dspex/tools/ → ../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/tools/
dspex/lib/dspex/bridge.ex (implementation) → ../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/dspy/
snakepit/priv/python/ → ../snakepit_grpc_bridge/priv/python/
dspex/priv/python/ → ../snakepit_grpc_bridge/priv/python/

CREATE (Clean APIs):
../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/variables.ex (new)
../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/tools.ex (new)
../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/api/dspy.ex (new)
../snakepit_grpc_bridge/lib/snakepit_grpc_bridge/adapter.ex (new)
```

### DSPex Simplification
```
KEEP (Orchestration Only):
dspex/lib/dspex.ex (update to use bridge APIs)
dspex/lib/dspex/bridge.ex (macro only, no implementation)

REMOVE (All Implementation):
dspex/lib/dspex/variables/ (moved to bridge)
dspex/lib/dspex/tools/ (moved to bridge)  
dspex/priv/python/ (moved to bridge)

CREATE (New Convenience):
dspex/lib/dspex/api.ex (high-level convenience functions)
dspex/lib/dspex/sessions.ex (session management helpers)
```

## Risk Mitigation

### 1. Backward Compatibility
- Keep existing DSPex APIs working during transition
- Provide deprecation warnings for removed functionality
- Offer migration scripts for major changes

### 2. Testing Strategy
- Comprehensive test suite for each package
- Integration tests across package boundaries
- Performance regression testing
- User acceptance testing

### 3. Rollback Plan
- Keep current implementation available as fallback
- Version lock dependencies during transition
- Staged rollout to minimize user impact

### 4. Communication Plan
- Announce migration timeline to users
- Provide regular progress updates
- Offer support during transition period

## Success Metrics

### 1. Architectural Goals
- [ ] Snakepit contains zero ML-specific code
- [ ] All Python code lives in SnakepitGRPCBridge
- [ ] DSPex is pure orchestration layer
- [ ] Clean separation of concerns achieved

### 2. User Experience
- [ ] All existing DSPex APIs still work
- [ ] Performance is maintained or improved
- [ ] Setup complexity is reduced
- [ ] Documentation is comprehensive

### 3. Developer Experience
- [ ] Each package has clear, single responsibility
- [ ] New features can be added to appropriate layer
- [ ] Independent teams can own different layers
- [ ] Code organization prevents "random dumping"

This migration plan provides a clear path to achieving the clean three-layer architecture while minimizing risk and maintaining user satisfaction.