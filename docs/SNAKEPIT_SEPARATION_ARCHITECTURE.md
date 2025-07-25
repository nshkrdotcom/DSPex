# Snakepit Separation Architecture Plan

## Executive Summary

This document outlines the architectural separation of Snakepit into two distinct packages:
- **Snakepit Core**: Pure infrastructure for pooling and session management
- **SnakepitGrpcBridge**: Domain-specific bridge for DSPy, gRPC, and variables functionality

This separation follows the Single Responsibility Principle, creates reusable infrastructure, and enables multiple bridge ecosystems while maintaining clean architectural boundaries.

## Current State Analysis

### Snakepit Today (Mixed Concerns)
```
snakepit/
├── lib/snakepit.ex                    # Core interface (197 lines)
├── lib/snakepit/pool/                 # Pure pooling logic ✅
├── lib/snakepit/session_helpers.ex    # Session management ✅
├── lib/snakepit/bridge/               # Bridge-specific logic ❌
├── lib/snakepit/variables.ex          # Variables system ❌
├── priv/python/                       # gRPC bridge code ❌
└── grpc/                              # gRPC infrastructure ❌
```

### Problem Statement
- **Mixed Responsibilities**: Infrastructure pooling mixed with domain-specific DSPy logic
- **Tight Coupling**: Variables, gRPC, and DSPy concerns tightly coupled to pooling
- **Limited Reusability**: Cannot use Snakepit pooling for non-DSPy bridges
- **Monolithic Architecture**: Single package handling orthogonal concerns

## Target Architecture

### Two-Package Separation
```
┌─────────────────────────────────────────────────────────────────┐
│                        User Applications                        │
│              (DSPex, custom ML apps, etc.)                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
     ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
     │snakepit_grpc_   │ │snakepit_json_   │ │snakepit_arrow_  │
     │    bridge       │ │    bridge       │ │    bridge       │
     │                 │ │   (future)      │ │   (future)      │
     └─────────────────┘ └─────────────────┘ └─────────────────┘
                │               │               │
                └───────────────┼───────────────┘
                                │
                    ┌─────────────────────────┐
                    │     snakepit (core)     │
                    │  Pure pooler + session  │
                    │      management         │
                    └─────────────────────────┘
```

## Package Specifications

### Snakepit Core (Infrastructure Only)

**Repository**: `snakepit` (existing, stripped down)  
**Version**: `0.4.0` (breaking change)  
**Dependencies**: Pure OTP/Elixir only

**Core Responsibilities:**
- Worker pool management and lifecycle
- Session affinity and routing
- Adapter pattern for external processes
- Streaming support infrastructure
- Performance monitoring and statistics

**API Surface:**
```elixir
defmodule Snakepit do
  # Core execution
  def execute(command, args, opts \\ [])
  def execute_in_session(session_id, command, args, opts \\ [])
  
  # Streaming support
  def execute_stream(command, args, callback_fn, opts \\ [])
  def execute_in_session_stream(session_id, command, args, callback_fn, opts \\ [])
  
  # Pool management
  def get_stats(pool \\ Snakepit.Pool)
  def list_workers(pool \\ Snakepit.Pool)
  
  # Script execution
  def run_as_script(fun, opts \\ [])
end
```

**Configuration:**
```elixir
config :snakepit,
  adapter_module: YourBridge.Adapter,
  pooling_enabled: true,
  pool_size: 4,
  worker_timeout: 30_000
```

### SnakepitGrpcBridge (Domain Logic)

**Repository**: `snakepit_grpc_bridge` (new package)  
**Version**: `0.1.0` (initial release)  
**Dependencies**: `{:snakepit, "~> 0.4"}, {:grpc, "~> 0.8"}`

**Core Responsibilities:**
- DSPy integration and schema discovery
- Variables system implementation
- gRPC protocol handling
- Tool calling infrastructure
- Python ↔ Elixir bidirectional communication

**API Surface:**
```elixir
defmodule SnakepitGrpcBridge do
  # Bridge lifecycle
  def start_bridge(config \\ [])
  def stop_bridge()
  
  # DSPy operations
  def execute_dspy(session_id, command, args)
  def discover_schema(module_path, opts \\ [])
  
  # Variables operations (delegated from DSPex.Variables)
  def get_variable(session_id, identifier, default \\ nil)
  def set_variable(session_id, identifier, value, opts \\ [])
  def list_variables(session_id)
  
  # Tool registration
  def register_elixir_tool(session_id, name, function, metadata)
  def list_elixir_tools(session_id)
end
```

## Architectural Benefits

### 1. Single Responsibility Principle
- **Snakepit**: Pure infrastructure concerns (pooling, sessions, adapters)
- **Bridge**: Domain-specific logic (DSPy, gRPC, variables)

### 2. Dependency Inversion
```
Application Layer    →  SnakepitGrpcBridge
Domain Layer        →  (Bridge-specific logic)
Infrastructure      →  Snakepit Core
```

### 3. Extensibility
```elixir
# Different bridges for different protocols
{:snakepit_grpc_bridge, "~> 0.1"}      # gRPC + DSPy
{:snakepit_json_bridge, "~> 0.1"}      # JSON-RPC bridge
{:snakepit_arrow_bridge, "~> 0.1"}     # Apache Arrow bridge
```

### 4. Independent Evolution
- **Snakepit Core**: Stable infrastructure, infrequent releases
- **Bridges**: Rapid iteration on domain-specific features

## Integration Patterns

### Adapter Registration
```elixir
# In bridge package
defmodule SnakepitGrpcBridge.Adapter do
  @behaviour Snakepit.Adapter
  
  def execute(command, args, opts) do
    case command do
      "call_dspy_bridge" -> 
        SnakepitGrpcBridge.DSPy.execute_command(args, opts)
      "get_variable" -> 
        SnakepitGrpcBridge.Variables.get(args["session_id"], args["identifier"])
      "discover_dspy_schema" -> 
        SnakepitGrpcBridge.DSPy.discover_schema(args["module_path"])
      _ -> 
        {:error, :unknown_command}
    end
  end
  
  def uses_grpc?, do: true
  def supports_streaming?, do: true
end
```

### Session Integration
```elixir
# Bridge provides session-aware operations
defmodule SnakepitGrpcBridge.Session do
  def initialize_session(session_id, config) do
    # Set up gRPC worker, variables store, tool registry
    with {:ok, _} <- setup_grpc_worker(session_id),
         {:ok, _} <- initialize_variables_store(session_id),
         {:ok, _} <- register_standard_tools(session_id) do
      {:ok, session_id}
    end
  end
  
  def cleanup_session(session_id) do
    # Clean up all session-specific resources
    cleanup_variables(session_id)
    cleanup_tools(session_id)
    cleanup_grpc_context(session_id)
  end
end
```

## Migration Strategy

### Phase 1: Package Separation (Week 1-2)
1. **Extract Snakepit Core**
   - Remove bridge-specific modules
   - Keep only pool, session helpers, adapter interface
   - Update configuration and documentation

2. **Create SnakepitGrpcBridge Package**
   - Move `lib/snakepit/bridge/` → `snakepit_grpc_bridge/lib/`
   - Move `priv/python/` → `snakepit_grpc_bridge/priv/`
   - Move `grpc/` → `snakepit_grpc_bridge/grpc/`
   - Implement `Snakepit.Adapter` behavior

### Phase 2: API Stabilization (Week 3)
1. **Update DSPex Integration**
   - Change dependency from `snakepit` to `snakepit_grpc_bridge`
   - Update `DSPex.Bridge` to use new bridge APIs
   - Maintain backward compatibility where possible

2. **Testing and Validation**
   - Comprehensive integration testing
   - Performance regression testing
   - Migration path validation

### Phase 3: Documentation and Release (Week 4)
1. **Documentation Updates**
   - Separate documentation for each package
   - Migration guides for existing users
   - Architecture decision records

2. **Release Management**
   - Snakepit 0.4.0 (breaking change)
   - SnakepitGrpcBridge 0.1.0 (initial release)
   - DSPex 0.4.0 (updated dependencies)

## File Structure After Separation

### Snakepit Core
```
snakepit/
├── lib/
│   ├── snakepit.ex                    # Core public API
│   ├── snakepit/
│   │   ├── pool/
│   │   │   ├── pool.ex               # Pool management
│   │   │   ├── registry.ex           # Worker registry
│   │   │   └── worker_starter_registry.ex
│   │   ├── session_helpers.ex        # Session utilities
│   │   └── adapter.ex                # Adapter behavior
│   └── mix.exs
├── test/
└── README.md
```

### SnakepitGrpcBridge
```
snakepit_grpc_bridge/
├── lib/
│   ├── snakepit_grpc_bridge.ex       # Main bridge API
│   ├── snakepit_grpc_bridge/
│   │   ├── adapter.ex                # Snakepit adapter implementation
│   │   ├── dspy/
│   │   │   ├── bridge.ex             # DSPy integration
│   │   │   ├── schema.ex             # Schema discovery
│   │   │   └── tools.ex              # Tool calling
│   │   ├── variables/
│   │   │   ├── store.ex              # Variables implementation
│   │   │   └── session.ex            # Session variables
│   │   ├── grpc/
│   │   │   ├── server.ex             # gRPC server
│   │   │   ├── client.ex             # gRPC client
│   │   │   └── protocols.ex          # Protocol definitions
│   │   └── session.ex                # Session management
│   └── mix.exs
├── priv/
│   └── python/                       # Python bridge code
├── grpc/                             # gRPC definitions
├── test/
└── README.md
```

## Success Criteria

### Technical Metrics
- [ ] Snakepit core < 1000 lines of code
- [ ] Zero performance regression in pooling operations
- [ ] 100% backward compatibility for DSPex users
- [ ] Independent CI/CD for both packages

### Architectural Validation
- [ ] Bridge can be swapped without changing Snakepit
- [ ] Multiple bridge types can coexist
- [ ] Clean dependency graph (Bridge → Snakepit, never reverse)
- [ ] Session affinity preserved across package boundary

### Developer Experience
- [ ] Simple migration path for existing users
- [ ] Clear documentation for both packages
- [ ] Separate issue tracking and release cycles
- [ ] Independent version management

## Risk Mitigation

### Integration Complexity
- **Risk**: Coordination overhead between packages
- **Mitigation**: Well-defined adapter interface, comprehensive integration tests

### Performance Impact
- **Risk**: Additional abstraction layers affecting performance
- **Mitigation**: Benchmarking throughout migration, direct call optimization

### Migration Difficulty
- **Risk**: Breaking changes for existing users
- **Mitigation**: Backward compatibility shims, automated migration tools

### Maintenance Burden
- **Risk**: Multiple repositories to maintain
- **Mitigation**: Automated CI/CD, clear ownership boundaries

## Future Extensibility

This architecture enables:
- **Multiple Bridge Types**: JSON-RPC, Apache Arrow, direct TCP bridges
- **Specialized Bridges**: ML-specific, database-specific, queue-specific bridges  
- **Third-Party Ecosystem**: Community bridges for different protocols
- **Snakepit Evolution**: Core infrastructure improvements benefit all bridges

The separation creates a solid foundation for a broader ecosystem of bridge types while keeping the core infrastructure simple, stable, and reusable.