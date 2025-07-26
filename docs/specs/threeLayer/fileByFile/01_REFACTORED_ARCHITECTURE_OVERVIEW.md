# Refactored Architecture Overview

## Executive Summary

This document presents a refactored architecture that addresses the critiques of over-abstraction and "cognitive" buzzwords. The focus is on **practical engineering benefits**: observability, maintainability, and the powerful bidirectional tool bridge.

## Three-Layer Architecture

### Layer 1: Snakepit Core (Infrastructure)
**Purpose**: Pure OTP infrastructure for process management
**Size**: ~1,500 lines (estimate as of 2024-01)
**Responsibilities**:
- Worker pool management
- Session routing
- Basic telemetry
- Adapter behavior definition

### Layer 2: SnakepitGrpcBridge (Bridge Implementation)
**Purpose**: gRPC bridge with comprehensive observability
**Size**: ~7,000 lines (estimate as of 2024-01)
**Responsibilities**:
- gRPC server/client implementation
- Session and variable storage
- Tool registry and execution
- Performance monitoring
- Bidirectional communication

### Layer 3: DSPex (User API)
**Purpose**: Clean, ergonomic Elixir API for AI tasks
**Size**: ~6,000 lines (estimate as of 2024-01)
**Responsibilities**:
- High-level DSPy integration
- Native Elixir components (Signature, Template, Validator)
- LLM adapter abstraction
- Developer-friendly APIs

## Key Architectural Changes

### 1. Decomposed defdsyp Macro

**Before**: One "god macro" trying to do everything
```elixir
defdsyp MyModule, "dspy.Predict", %{
  enhanced_mode: true,
  elixir_tools: ["tool1", "tool2"],
  result_transform: &transform/1
}
```

**After**: Explicit, composable components
```elixir
defmodule MyApp.Predictor do
  use DSPex.Bridge.SimpleWrapper
  
  # Simple wrapper generation
  wrap_dspy "dspy.Predict"
  
  # Explicit bidirectional features
  use DSPex.Bridge.Bidirectional
  
  @impl DSPex.Bridge.Bidirectional
  def elixir_tools do
    [
      {"validate_reasoning", &MyApp.Validators.validate_reasoning/1},
      {"process_template", &MyApp.Templates.process/1}
    ]
  end
  
  @impl DSPex.Bridge.Bidirectional
  def transform_result(result), do: MyApp.Transforms.prediction(result)
end
```

### 2. Contract-Based Wrappers

**Before**: Stringly-typed API
```elixir
Bridge.call_method(ref, "__call__", %{question: "..."})  # Hope the method exists!
```

**After**: Explicit contracts with compile-time validation
```elixir
# Define explicit contract (no Python needed at compile time!)
defmodule DSPex.Contracts.Predict do
  use DSPex.Contract
  
  @python_class "dspy.Predict"
  
  defmethod :create, :__init__,
    params: [signature: :string],
    returns: :reference
    
  defmethod :predict, :__call__,
    params: [question: :string],
    returns: {:ok, %Prediction{}}
end

# Use the contract
defmodule MyApp.Predictor do
  use DSPex.Bridge.ContractBased
  use_contract DSPex.Contracts.Predict
  
  # Typed functions generated from contract
end
```

### 3. Observable, Not "Cognitive"

**Before**: Vague "cognitive" features
```elixir
defmodule SnakepitGrpcBridge.Cognitive.Worker do
  # What does "cognitive" even mean?
end
```

**After**: Concrete, observable features
```elixir
defmodule SnakepitGrpcBridge.Observable.Worker do
  # Clear purpose: emit telemetry for monitoring
  
  def execute(command, args) do
    :telemetry.span([:worker, :execution], %{command: command}, fn ->
      result = do_execute(command, args)
      
      metadata = %{
        command: command,
        args_size: :erlang.external_size(args),
        success: match?({:ok, _}, result)
      }
      
      {result, metadata}
    end)
  end
end
```

### 4. Performance-Aware Routing

**Before**: "Cognitive scheduler with ML"
```elixir
defmodule Cognitive.Scheduler do
  # Magical ML-powered routing (someday)
end
```

**After**: Practical performance-based routing
```elixir
defmodule SnakepitGrpcBridge.Routing.PerformanceRouter do
  @moduledoc """
  Routes requests to workers based on actual performance data.
  No ML needed - just track execution times and route accordingly.
  """
  
  def route_request(command, args) do
    # Get performance stats from telemetry
    worker_stats = get_worker_performance_stats()
    
    # Simple heuristic: route to fastest worker for this command type
    fastest_worker = worker_stats
      |> Enum.filter(&(&1.command == command))
      |> Enum.min_by(&(&1.avg_execution_time))
      
    {:ok, fastest_worker.worker_id}
  end
end
```

## Bidirectional Tool Bridge (The Killer Feature)

### How It Works

1. **Elixir → Python**: Standard RPC
   ```elixir
   result = Bridge.call_dspy("dspy.Predict", "__call__", %{question: "What is AI?"})
   ```

2. **Python → Elixir**: The Magic
   ```python
   def enhanced_chain_of_thought(session_context, inputs):
       # Step 1: Generate initial reasoning
       reasoning = generate_reasoning(inputs)
       
       # Step 2: Validate reasoning using Elixir business logic
       is_valid = session_context.call_elixir_tool("validate_reasoning", {
           "reasoning": reasoning,
           "context": inputs
       })
       
       if not is_valid:
           # Step 3: Apply business rules from Elixir
           reasoning = session_context.call_elixir_tool("apply_reasoning_rules", {
               "raw_reasoning": reasoning
           })
       
       # Step 4: Process template using Elixir's pattern matching
       final_output = session_context.call_elixir_tool("process_template", {
           "template": "reasoning_template",
           "data": reasoning
       })
       
       return final_output
   ```

### Why This Matters

- **Business Logic Stays in Elixir**: Validation rules, data transformations, and domain logic remain in the robust Elixir environment
- **Python Focuses on AI**: Python workers handle what they do best - ML inference and probabilistic reasoning
- **True Collaboration**: Not just Elixir calling Python, but Python calling back to Elixir for help

## Observable Features

### 1. Performance Monitoring
Every operation emits telemetry with:
- Execution duration
- Success/failure status
- Input/output sizes
- Memory usage

### 2. Error Pattern Tracking
The system tracks:
- Common error types by operation
- Failure rates by worker
- Recovery patterns

### 3. Usage Analytics
Understand your system with:
- Most-used operations
- Peak usage times
- Resource utilization patterns

### 4. Practical Optimizations
Based on real data, not speculation:
- Route to fastest workers
- Cache frequent operations
- Preload common schemas

## Migration Benefits

### From Abstract to Concrete

| Old "Cognitive" Feature | New Observable Feature | Actual Benefit |
|------------------------|----------------------|----------------|
| Cognitive Worker | Observable Worker | Detailed performance metrics |
| Cognitive Scheduler | Performance Router | Routes to fastest worker |
| Cognitive Evolution | Usage Analytics | Understand what's actually used |
| Wrapper Optimization | Schema Caching | Faster startup times |

### Developer Experience Improvements

1. **Less Magic**: Explicit modules and functions instead of complex macros
2. **Better Errors**: Schema validation catches issues at compile time
3. **Easier Debugging**: Clear telemetry shows exactly what's happening
4. **Maintainable**: Smaller, focused modules instead of god objects

## Summary

This refactored architecture delivers the same powerful functionality with:
- **Less Complexity**: Decomposed abstractions are easier to understand
- **More Observability**: Comprehensive telemetry instead of vague "cognitive" promises
- **Better DX**: Clear, explicit APIs instead of magic
- **Same Innovation**: The bidirectional tool bridge remains the killer feature

The result is a system that's both powerful and maintainable, innovative yet grounded in practical engineering.