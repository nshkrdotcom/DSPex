# DSPex Dual Implementation Support Architecture

## Executive Summary

This document outlines the architecture for seamlessly supporting both native Elixir and Python DSPy implementations within DSPex. The design allows gradual migration from Python-backed modules to native implementations while maintaining a stable, unified API for users.

## Architecture Overview

### Core Principle

DSPex provides a unified interface that automatically routes to the best available implementation:
- **Native Elixir**: Direct BEAM execution for maximum performance
- **Python DSPy**: Via Snakepit for modules not yet ported

### Key Design Decisions

1. **No Snakepit for Native Code**: Native implementations run directly in BEAM
2. **Transparent Routing**: Users don't need to know which implementation is used
3. **Gradual Migration**: Port modules one at a time without breaking changes
4. **Performance First**: Native implementations get priority when available

## Implementation Architecture

### 1. Module Reference Structure

Each DSPex module returns a tagged reference indicating its implementation:

```elixir
# Native implementation returns
{:ok, {:native, %NativeModuleState{}}}

# Python implementation returns  
{:ok, {:python, session_id, module_id}}
```

### 2. Unified Module Interface

All convenience wrappers follow this pattern:

```elixir
defmodule DSPex.Modules.ChainOfThought do
  @moduledoc """
  Chain of Thought reasoning module.
  Automatically routes to native or Python implementation.
  """
  
  def create(signature, opts \\ []) do
    case select_implementation(opts) do
      :native ->
        DSPex.Native.ChainOfThought.create(signature, opts)
        
      :python ->
        session_id = ensure_session(opts)
        id = DSPex.Utils.ID.generate("cot")
        
        case Snakepit.Python.call("dspy.ChainOfThought", 
          %{signature: signature}, 
          [store_as: id, session_id: session_id] ++ opts) do
          {:ok, _} -> {:ok, {:python, session_id, id}}
          error -> error
        end
    end
  end
  
  def execute({:native, module_state}, inputs, opts) do
    DSPex.Native.ChainOfThought.execute(module_state, inputs, opts)
  end
  
  def execute({:python, session_id, module_id}, inputs, opts) do
    Snakepit.Python.call("stored.#{module_id}.__call__", inputs, 
      [session_id: session_id] ++ opts)
  end
  
  defp select_implementation(opts) do
    cond do
      opts[:implementation] == :native && native_available?() -> :native
      opts[:implementation] == :python -> :python
      native_available?() && prefer_native?() -> :native
      true -> :python
    end
  end
  
  defp native_available? do
    Code.ensure_loaded?(DSPex.Native.ChainOfThought)
  end
  
  defp prefer_native? do
    Application.get_env(:dspex, :prefer_native, true)
  end
end
```

### 3. Implementation Registry

Track which modules have native implementations:

```elixir
defmodule DSPex.Implementation.Registry do
  @moduledoc """
  Registry of available implementations for each DSPex module.
  """
  
  @native_implementations %{
    # Already native
    signature: true,
    template: true,
    validator: true,
    metrics: true,
    
    # Python only (for now)
    predict: false,
    chain_of_thought: false,
    react: false,
    program_of_thought: false,
    multi_chain_comparison: false,
    retry: false,
    
    # Optimizers
    bootstrap_few_shot: false,
    mipro: false,
    mipro_v2: false,
    copro: false,
    
    # Retrievers
    colbert_v2: false,
    retrieve: false
  }
  
  def has_native?(module_type) do
    Map.get(@native_implementations, module_type, false)
  end
  
  def list_by_implementation do
    Enum.group_by(@native_implementations, fn {_, native} -> 
      if native, do: :native, else: :python
    end)
  end
end
```

### 4. Router Enhancement

The existing Router module handles implementation selection:

```elixir
defmodule DSPex.Router do
  @moduledoc """
  Routes operations to appropriate implementations with telemetry.
  """
  
  def route(operation, module_type, args, opts) do
    implementation = select_implementation(module_type, opts)
    
    :telemetry.execute(
      [:dspex, :router, :route],
      %{timestamp: System.monotonic_time()},
      %{
        operation: operation,
        module_type: module_type,
        implementation: implementation,
        native_available: DSPex.Implementation.Registry.has_native?(module_type)
      }
    )
    
    case implementation do
      :native ->
        route_to_native(operation, module_type, args, opts)
        
      :python ->
        route_to_python(operation, module_type, args, opts)
    end
  end
  
  defp route_to_native(operation, module_type, args, opts) do
    module = Module.concat([DSPex, Native, Macro.camelize(to_string(module_type))])
    apply(module, operation, [args, opts])
  end
  
  defp route_to_python(operation, module_type, args, opts) do
    # Use existing Python bridge via Snakepit
    DSPex.Python.Bridge.execute(nil, operation, args, opts)
  end
end
```

### 5. Session Management Abstraction

Hide session complexity from users:

```elixir
defmodule DSPex.Session do
  @moduledoc """
  Unified session management for both native and Python implementations.
  """
  
  def with_session(fun, opts \\ []) do
    case determine_session_need(opts) do
      :none ->
        # Native implementation, no session needed
        fun.(opts)
        
      :python ->
        # Python implementation needs Snakepit session
        session_id = Snakepit.Python.create_session()
        try do
          fun.(Keyword.put(opts, :session_id, session_id))
        after
          Snakepit.Python.destroy_session(session_id)
        end
    end
  end
  
  defp determine_session_need(opts) do
    if opts[:implementation] == :native || all_native?(opts[:modules]) do
      :none
    else
      :python
    end
  end
end
```

## Migration Path

### Phase 1: Python-First (Current State)
- All DSPy modules implemented via Python wrappers
- Snakepit handles all execution
- Native only for signatures, templates, validators

### Phase 2: High-Value Native Modules
Priority modules to implement natively:
1. **Predict** - Most basic, high-frequency operation
2. **ChainOfThought** - Popular reasoning module
3. **Evaluation.Metrics** - Performance-critical scoring

### Phase 3: Optimizers
Native implementations of optimization algorithms:
1. **BootstrapFewShot** - Most commonly used
2. **MIPRO/MIPROv2** - Complex but high-value

### Phase 4: Advanced Modules
1. **ReAct** - Requires tool integration design
2. **Retrievers** - May keep some as Python for vector DB compatibility

## Configuration

```elixir
# config/config.exs
config :dspex,
  # Implementation preferences
  prefer_native: true,              # Use native when available
  allow_fallback: true,            # Fall back to Python if native fails
  
  # Module-specific overrides
  implementation_overrides: %{
    # Force specific implementations
    chain_of_thought: :python,     # Use Python even if native exists
    predict: :native               # Use native even in Python-first mode
  },
  
  # Performance settings
  implementation_cache: true,       # Cache implementation decisions
  telemetry_enabled: true          # Track implementation usage
```

## Usage Examples

### Basic Usage (Implementation Transparent)

```elixir
# Users don't need to know which implementation is used
{:ok, cot} = DSPex.Modules.ChainOfThought.create("question -> answer")
{:ok, result} = DSPex.Modules.ChainOfThought.execute(cot, %{
  question: "What is machine learning?"
})
```

### Forcing Implementation

```elixir
# Force native implementation
{:ok, cot} = DSPex.Modules.ChainOfThought.create(
  "question -> answer",
  implementation: :native
)

# Force Python implementation
{:ok, cot} = DSPex.Modules.ChainOfThought.create(
  "question -> answer", 
  implementation: :python
)
```

### Mixed Pipeline

```elixir
# Pipeline automatically uses best implementation for each step
pipeline = DSPex.pipeline([
  # Native signature parsing
  {:native, DSPex.Native.Signature, spec: "query -> keywords: list[str]"},
  
  # Python ChainOfThought (not yet native)
  {:auto, DSPex.Modules.ChainOfThought, signature: "keywords -> analysis"},
  
  # Native template rendering
  {:native, DSPex.Native.Template, template: "Analysis: <%= @analysis %>"}
])

{:ok, result} = DSPex.run_pipeline(pipeline, %{query: "explain DSPy"})
```

## Performance Characteristics

### Native Implementations
- **Latency**: < 0.1ms for most operations
- **Throughput**: 500k+ ops/sec
- **Memory**: Shared BEAM memory, no serialization
- **Scaling**: Limited by BEAM scheduler

### Python Implementations (via Snakepit)
- **Latency**: 2-100ms depending on operation
- **Throughput**: 1k-50k ops/sec
- **Memory**: Separate Python processes, serialization overhead
- **Scaling**: Limited by pool size and Python GIL

## Testing Strategy

### 1. Implementation Parity Tests

```elixir
defmodule DSPex.Test.ParityTest do
  use ExUnit.Case
  
  @modules_with_native [:predict, :chain_of_thought]
  
  for module <- @modules_with_native do
    test "#{module} native and Python produce equivalent results" do
      signature = "input -> output"
      inputs = %{input: "test"}
      
      # Test Python implementation
      {:ok, py_mod} = DSPex.Modules.unquote(module).create(
        signature, 
        implementation: :python
      )
      {:ok, py_result} = DSPex.Modules.unquote(module).execute(py_mod, inputs)
      
      # Test native implementation
      {:ok, native_mod} = DSPex.Modules.unquote(module).create(
        signature,
        implementation: :native
      )
      {:ok, native_result} = DSPex.Modules.unquote(module).execute(
        native_mod, 
        inputs
      )
      
      # Results should be equivalent
      assert equivalent_results?(py_result, native_result)
    end
  end
end
```

### 2. Performance Benchmarks

```elixir
defmodule DSPex.Benchmark do
  def compare_implementations(module_type, inputs) do
    Benchee.run(%{
      "native" => fn ->
        {:ok, m} = DSPex.Modules.create(module_type, "input -> output", 
          implementation: :native)
        DSPex.Modules.execute(m, inputs)
      end,
      "python" => fn ->
        {:ok, m} = DSPex.Modules.create(module_type, "input -> output",
          implementation: :python)
        DSPex.Modules.execute(m, inputs)
      end
    })
  end
end
```

## Benefits

1. **Seamless Migration**: Port modules without changing user code
2. **Performance Optimization**: Native modules run at full BEAM speed
3. **Flexibility**: Choose implementation based on needs
4. **Gradual Adoption**: No "big bang" migration required
5. **Fallback Safety**: Python implementation always available
6. **Clean Architecture**: Clear separation of concerns

## Future Considerations

### WebAssembly Integration
- Potential third implementation type for compute-intensive operations
- Would follow same pattern: `{:wasm, module_ref}`

### Distributed Execution
- Native implementations can leverage distributed BEAM
- Python implementations could use distributed Snakepit pools

### Hot Code Reloading
- Native implementations support BEAM hot code reloading
- Python implementations require session restart

## Conclusion

This dual implementation architecture allows DSPex to evolve from a Python DSPy bridge to a native Elixir implementation while maintaining API stability. Users get the best of both worlds: immediate access to all DSPy functionality via Python, with gradual performance improvements as modules are ported to native Elixir.