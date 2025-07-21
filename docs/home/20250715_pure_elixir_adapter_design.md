# Pure Elixir Adapter Design for DSPex
**Date: 2025-07-15**

## Executive Summary

This document outlines the design for integrating pure Elixir adapters into the DSPex system alongside the existing Python/DSPy adapters. The goal is to provide a high-performance, pure Elixir alternative that shares the same interface as Python adapters while offering flexibility in deployment configurations.

## Current Architecture Analysis

### Adapter Pattern Implementation

DSPex implements a sophisticated adapter pattern with clear separation of concerns:

1. **Adapter Behaviour** (`DSPex.Adapters.Adapter`)
   - Defines the contract: `create_program/1`, `execute_program/2`, `list_programs/0`, `delete_program/1`
   - Optional callbacks for enhanced functionality
   - Test layer support built-in

2. **Existing Adapters**
   - **Mock**: Pure Elixir for testing (Layer 1)
   - **BridgeMock**: Protocol validation (Layer 2)  
   - **PythonPort**: Direct port communication (Layer 3)
   - **PythonPool/PythonPoolV2**: Pooled Python workers

### SessionPoolV2 Architecture

The pool system is already designed for flexibility:
- Configurable `worker_module` parameter (defaults to `PoolWorkerV2`)
- Workers implement `NimblePool` behaviour
- Session affinity and state management via `SessionStore`
- Comprehensive error handling and monitoring

## Design Options

### Option 1: Direct Pure Elixir Adapter (No Pooling)

A simple adapter that implements `DSPex.Adapters.Adapter` directly without pooling:

```elixir
defmodule DSPex.Adapters.PureElixir do
  @behaviour DSPex.Adapters.Adapter
  
  # Direct implementation without pooling
  # State managed in ETS/GenServer
  # Suitable for CPU-bound Elixir computations
end
```

**Pros:**
- Simple implementation
- No pooling overhead
- Direct execution path
- Ideal for stateless operations

**Cons:**
- No built-in concurrency limits
- Manual state management required
- Different operational model from Python adapters

### Option 2: Pooled Pure Elixir Workers

Create `ElixirWorkerV2` that implements `NimblePool` behaviour:

```elixir
defmodule DSPex.ElixirBridge.ElixirWorkerV2 do
  @behaviour NimblePool
  
  # Implements same interface as PoolWorkerV2
  # But executes Elixir code instead of Python
  # Can be used with SessionPoolV2
end
```

**Pros:**
- Reuses existing pool infrastructure
- Consistent operational model
- Built-in concurrency control
- Session affinity support

**Cons:**
- Pooling overhead for pure Elixir
- More complex implementation

### Option 3: Hybrid Adapter System (Recommended)

A generalized solution supporting both Python and Elixir backends:

```elixir
defmodule DSPex.Adapters.Hybrid do
  @behaviour DSPex.Adapters.Adapter
  
  # Configuration-based backend selection
  def init(opts) do
    backend = Keyword.get(opts, :backend, :python)
    case backend do
      :python -> init_python_pool(opts)
      :elixir_pooled -> init_elixir_pool(opts)
      :elixir_direct -> init_elixir_direct(opts)
    end
  end
end
```

## Recommended Implementation Plan

### Phase 1: Pure Elixir Direct Adapter

Create a simple, non-pooled pure Elixir adapter:

```elixir
defmodule DSPex.Adapters.ElixirDirect do
  @moduledoc """
  Pure Elixir adapter for high-performance ML operations.
  
  Features:
  - Direct execution without pooling overhead
  - In-memory program storage
  - Native Elixir ML operations
  - Compatible with existing adapter interface
  """
  
  @behaviour DSPex.Adapters.Adapter
  use GenServer
  
  # Implement adapter callbacks
  def create_program(config) do
    # Store program definition in ETS/State
    # Return program_id
  end
  
  def execute_program(program_id, inputs) do
    # Execute Elixir-based ML logic
    # Return results
  end
end
```

### Phase 2: Pooled Elixir Workers

Create ElixirWorkerV2 for pooled operations:

```elixir
defmodule DSPex.ElixirBridge.ElixirWorkerV2 do
  @behaviour NimblePool
  
  defstruct [:worker_id, :state, :programs]
  
  @impl NimblePool
  def init_worker(pool_state) do
    # Initialize Elixir worker
    # No port, just internal state
  end
  
  # Reuse execute_with_worker pattern from SessionPoolV2
end
```

### Phase 3: Unified Configuration

Extend the Registry to support backend selection:

```elixir
# In config/config.exs
config :dspex, :adapters,
  default: :hybrid,
  hybrid_config: %{
    python_backend: :pool_v2,  # or :direct
    elixir_backend: :direct,   # or :pooled
    routing_rules: [
      # Route specific operations to specific backends
      {:create_program, :signature_type, "chain_of_thought", :python},
      {:execute_program, :program_type, "simple_predict", :elixir}
    ]
  }
```

## Integration with Existing System

### 1. Adapter Factory Enhancement

```elixir
defmodule DSPex.Adapters.Factory do
  def create(adapter_name, config) do
    case adapter_name do
      :pure_elixir -> DSPex.Adapters.ElixirDirect.start_link(config)
      :elixir_pooled -> create_elixir_pool(config)
      :hybrid -> DSPex.Adapters.Hybrid.start_link(config)
      # ... existing adapters
    end
  end
  
  defp create_elixir_pool(config) do
    # Configure SessionPoolV2 with ElixirWorkerV2
    pool_config = Keyword.merge(config, [
      worker_module: DSPex.ElixirBridge.ElixirWorkerV2
    ])
    DSPex.PythonBridge.SessionPoolV2.start_link(pool_config)
  end
end
```

### 2. Router Pattern for Dual Support

```elixir
defmodule DSPex.Adapters.Router do
  @behaviour DSPex.Adapters.Adapter
  
  def create_program(config) do
    backend = select_backend(config)
    backend.create_program(config)
  end
  
  defp select_backend(config) do
    # Logic to choose Python vs Elixir based on:
    # - Program type (signature complexity)
    # - Performance requirements
    # - Available resources
    # - Configuration preferences
  end
end
```

## Performance Considerations

### When to Use Each Approach

**Pure Elixir Direct (No Pooling)**
- Simple predict operations
- High-frequency, low-latency requirements
- Stateless transformations
- CPU-bound computations in Elixir

**Pure Elixir Pooled**
- Long-running Elixir computations
- Stateful ML models in Elixir
- Resource-constrained environments
- Need for backpressure control

**Python Pooled (Existing)**
- Complex DSPy programs
- GPU-accelerated operations
- Integration with Python ML ecosystem
- Existing DSPy chains and prompts

## Example Usage

### Configuration
```elixir
# Pure Elixir adapter (no pooling)
config :dspex, :adapters,
  default: :pure_elixir

# Hybrid adapter with routing
config :dspex, :adapters,
  default: :hybrid,
  hybrid_config: %{
    elixir_programs: ["simple_classifier", "text_embedder"],
    python_programs: ["chain_of_thought", "rag_pipeline"]
  }

# Pooled Elixir workers
config :dspex, DSPex.PythonBridge.SessionPoolV2,
  worker_module: DSPex.ElixirBridge.ElixirWorkerV2,
  pool_size: 8
```

### Client Code (Unchanged)
```elixir
# Works with any adapter configuration
{:ok, program_id} = DSPex.create_program(%{
  signature: %{input: "text", output: "classification"},
  adapter: :auto  # Automatically selects best backend
})

{:ok, result} = DSPex.execute(program_id, %{text: "Hello world"})
```

## Migration Strategy

1. **Phase 1**: Implement ElixirDirect adapter for simple use cases
2. **Phase 2**: Add ElixirWorkerV2 for pooled operations
3. **Phase 3**: Implement Router/Hybrid adapter
4. **Phase 4**: Gradual migration of suitable operations to Elixir

## Benefits of This Design

1. **Flexibility**: Choose pooling strategy per use case
2. **Performance**: Eliminate Python overhead for simple operations
3. **Compatibility**: Maintains existing adapter interface
4. **Gradual Migration**: Can move operations incrementally
5. **Resource Optimization**: Use appropriate backend for each task
6. **Hot Path Optimization**: Pure Elixir for high-frequency operations

## Implementation Priority

1. **Immediate**: ElixirDirect adapter (no pooling) for simple operations
2. **Short-term**: ElixirWorkerV2 for pooled Elixir operations
3. **Medium-term**: Hybrid/Router adapter for intelligent backend selection
4. **Long-term**: Full integration with monitoring, metrics, and error handling

## Conclusion

The DSPex architecture is already well-prepared for pure Elixir adapters. The modular design allows for:
- Non-pooled Elixir adapter for maximum performance
- Pooled Elixir workers using existing SessionPoolV2
- Hybrid approach selecting optimal backend per operation

This design maintains backward compatibility while providing a path to high-performance pure Elixir execution for suitable workloads.