# REPORT_INFRASTRUCTURE.md
## Sub-Agent 1: The Infrastructure Purifier

**Persona:** A senior infrastructure engineer focused on reliability and abstraction.  
**Scope:** Analyze the *current* `snakepit` application (`./snakepit/lib`, `./snakepit/priv`).  
**Mission:** Identify everything that does NOT belong in a pure infrastructure layer. Define the boundaries of the new, lightweight `snakepit`.

---

## 1. Core Infrastructure Components to Keep

### Essential Pooling Infrastructure (`/lib/snakepit/pool/`)
- **`pool.ex`** - Core process pooling logic with worker management
  - Justification: Pure infrastructure concern for managing external process pools
- **`registry.ex`** - Worker registry for tracking available/busy workers  
  - Justification: Essential infrastructure for load balancing and worker state
- **`worker_supervisor.ex`** - Dynamic supervision of worker processes
  - Justification: Core OTP pattern for fault tolerance
- **`worker_starter.ex` & `worker_starter_registry.ex`** - Concurrent worker startup
  - Justification: Infrastructure concern for efficient pool initialization

### Process Lifecycle Management (`/lib/snakepit/pool/`)
- **`process_registry.ex`** - OS PID tracking and orphan prevention (using DETS)
  - Justification: Critical infrastructure for preventing zombie processes
- **`application_cleanup.ex`** - Graceful shutdown and cleanup guarantees
  - Justification: Infrastructure requirement for production stability

### Core Adapter & Worker Components (`/lib/snakepit/`)
- **`adapter.ex`** - The behavior definition for pluggable bridges
  - Justification: The key abstraction enabling protocol-agnostic design
- **`generic_worker.ex`** - Generic worker implementation using adapters
  - Justification: Infrastructure pattern for worker lifecycle
- **`session_helpers.ex`** - Session affinity routing infrastructure
  - Justification: Generic routing concern, not ML-specific

### Application Infrastructure (`/lib/snakepit/`)
- **`application.ex`** - OTP application supervision tree
  - Justification: Core application lifecycle management
- **`telemetry.ex`** - Infrastructure metrics and monitoring
  - Justification: Generic observability, not domain-specific
- **`utils.ex`** - Generic utility functions
  - Justification: Infrastructure helpers

### Data Storage (`/priv/data/`)
- **`process_registry.dets`** - Persistent process tracking storage
  - Justification: Infrastructure persistence requirement

## 2. Components to Be Removed/Migrated

### All Python Code (`/priv/python/`)
**Must Remove Entirely:**
- `grpc_server.py` - gRPC server implementation
  - Violation: Protocol-specific implementation belongs in platform layer
- `snakepit_bridge_pb2.py` & `snakepit_bridge_pb2_grpc.py` - Generated gRPC code
  - Violation: Protocol-specific, auto-generated from proto files
- `generate_proto.py` & `generate_grpc.sh` - Build tooling for gRPC
  - Violation: Protocol-specific tooling
- `test_server.py` - Python test server
  - Violation: Platform-specific testing

**`/priv/python/snakepit_bridge/` directory:**
- `dspy_integration.py` - DSPy module integration
  - Violation: ML domain logic, belongs in platform
- `variable_aware_mixin.py` - Variable system for ML
  - Violation: ML-specific feature
- `serialization.py` - Data serialization for bridge
  - Violation: Protocol implementation detail
- `session_context.py` - Session management for ML workflows
  - Violation: Domain-specific session handling
- `types.py` - Type definitions for bridge
  - Violation: Bridge-specific types
- **`/adapters/` subdirectory** - All adapter implementations
  - Violation: Specific bridge implementations belong in platform

### All Protocol Definitions (`/priv/proto/`)
- `snakepit_bridge.proto` - gRPC protocol definition
  - Violation: Communication protocol belongs with its implementation
- `README.md` in proto directory
  - Violation: Documentation for protocol-specific files

### Python Dependencies
- `requirements.txt` - Python package dependencies
  - Violation: Platform-specific dependencies
- `setup.py` - Python package configuration
  - Violation: Platform-specific packaging

### Build Artifacts
- `server.log` - Python server logs
  - Violation: Runtime artifact from platform layer
- `/venv/` directory (if present)
  - Violation: Python virtual environment

### Bridge-Specific Documentation
- Files containing gRPC/Python bridge specifics should be moved:
  - `README_BIDIRECTIONAL_TOOL_BRIDGE.md`
  - `README_GRPC.md`  
  - `README_UNIFIED_GRPC_BRIDGE.md`
  - Violation: These document platform-specific features

## 3. Refined `Snakepit.Adapter` Contract

Based on the analysis, the current adapter contract in `adapter.ex` is already well-designed for a pure infrastructure layer. The refined contract should maintain:

```elixir
defmodule Snakepit.Adapter do
  @moduledoc """
  Behavior for external process adapters.
  
  Defines the interface that bridge packages must implement to integrate
  with Snakepit Core infrastructure. Protocol-agnostic and domain-neutral.
  """

  # Core execution - the only required callback
  @callback execute(command :: String.t(), args :: map(), opts :: keyword()) :: 
    {:ok, term()} | {:error, term()}

  # Optional callbacks for enhanced functionality
  @callback execute_stream(command :: String.t(), args :: map(), 
                          callback :: (term() -> any()), opts :: keyword()) :: 
    :ok | {:error, term()}
  
  @callback supports_streaming?() :: boolean()
  
  # Process lifecycle callbacks
  @callback init(config :: keyword()) :: {:ok, state :: term()} | {:error, term()}
  
  @callback terminate(reason :: term(), state :: term()) :: term()
  
  @callback start_worker(adapter_state :: term(), worker_id :: term()) :: 
    {:ok, worker_pid :: pid()} | {:error, term()}

  # Remove cognitive/ML specific callbacks
  # The following should NOT be in the adapter:
  # - get_cognitive_metadata/0 (too domain-specific)
  # - report_performance_metrics/2 (can be generic telemetry instead)
  # - uses_grpc?/0 (protocol-specific)
end
```

### Key Refinements:
1. **Remove `uses_grpc?/0`** - Infrastructure shouldn't know about specific protocols
2. **Remove cognitive-specific callbacks** - Keep adapter focused on process management
3. **Keep streaming support** - This is a generic capability, not protocol-specific
4. **Maintain session helpers** - But ensure they remain generic routing utilities

### Adapter Usage Pattern:
```elixir
# Infrastructure only knows about generic execution
defmodule Snakepit.Pool do
  def execute(pool, command, args, opts) do
    # Get worker from pool
    worker = get_available_worker(pool)
    
    # Execute through adapter - no protocol knowledge
    adapter = get_adapter(pool)
    adapter.execute(command, args, [{:worker_pid, worker} | opts])
  end
end
```

## Summary

The purified Snakepit infrastructure layer should contain ONLY:
- Generic process pooling and lifecycle management
- Worker supervision and fault tolerance
- OS process tracking and cleanup
- Session affinity routing (generic, not ML-specific)
- Adapter behavior for pluggable implementations
- Telemetry for infrastructure metrics

Everything else - all Python code, proto files, ML-specific logic, and protocol implementations - must be removed and relocated to the platform layer (`snakepit_grpc_bridge`).