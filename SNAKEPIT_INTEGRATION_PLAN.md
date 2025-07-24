# DSPex Integration Plan with Snakepit v0.4.0

## Overview

This document outlines the plan to revamp DSPex integration to use Snakepit's clean, unified gRPC architecture. Snakepit v0.4.0 provides a complete bridge with session management, tool execution, and Python interop - we should leverage it instead of maintaining a parallel bridge.

## Current State Analysis

### DSPex Current Architecture
- Custom Python bridge implementation (`priv/python/dspy_bridge.py`)
- JSON-based protocol with length-prefixed messages
- Direct port communication
- Manual session and state management
- Complex error handling and protocol encoding/decoding

### Snakepit v0.4.0 Architecture
- Clean API: `Snakepit.execute/2`, `Snakepit.execute_in_session/3`
- Unified gRPC bridge with automatic serialization
- Built-in session management via SessionStore
- `Snakepit.Python.call/3` for dynamic Python method invocation
- Automatic binary serialization for large data (tensors/embeddings)
- Tool registration and discovery system

## Integration Strategy

### Phase 1: Direct API Migration

Replace DSPex's custom bridge calls with Snakepit's clean API:

#### Before (DSPex current):
```elixir
# In DSPex.Config
case Snakepit.Python.call("dspy.__version__", %{}, opts) do
  {:ok, %{"result" => version}} -> {:ok, version}
  {:error, _} -> {:error, "DSPy not found"}
end
```

#### After (using Snakepit properly):
```elixir
# Already works! Snakepit.Python.call handles this correctly
case Snakepit.Python.call("dspy.__version__", %{}, opts) do
  {:ok, %{"result" => version}} -> {:ok, version}
  {:error, _} -> {:error, "DSPy not found"}
end
```

### Phase 2: Module Refactoring

Update DSPex modules to use Snakepit's session management:

#### Before:
```elixir
# DSPex.Modules.Predict
def create(signature, opts \\ []) do
  predictor_id = "predict_#{:erlang.unique_integer([:positive])}"
  args = %{
    id: predictor_id,
    signature: prepare_signature(signature),
    program_type: "predict"
  }
  case Snakepit.Python.call("create_program", args, opts) do
    {:ok, _} -> {:ok, predictor_id}
    error -> error
  end
end
```

#### After:
```elixir
# Using Snakepit's clean approach
def create(signature, opts \\ []) do
  predictor_id = "predict_#{:erlang.unique_integer([:positive])}"
  
  # Create DSPy program using Python.call
  case Snakepit.Python.call("dspy.Predict", 
    %{signature: signature}, 
    store_as: predictor_id
  ) do
    {:ok, _} -> {:ok, predictor_id}
    error -> error
  end
end

def execute(predictor_id, inputs, opts \\ []) do
  # Direct call to stored object
  Snakepit.Python.call("stored.#{predictor_id}", inputs, opts)
end
```

### Phase 3: Adapter Selection

Configure DSPex to use the appropriate Snakepit adapter:

```elixir
# config/config.exs
config :snakepit,
  pools: [
    default: [
      size: 4,
      adapter: Snakepit.Adapters.GRPCPython,
      adapter_args: [
        # Can use our DSPy adapter or the enhanced adapter
        "--adapter", "snakepit_bridge.adapters.dspy_grpc.DSPyGRPCHandler"
      ]
    ]
  ]
```

### Phase 4: Session Management

Leverage Snakepit's session management for stateful operations:

```elixir
defmodule DSPex.Session do
  @moduledoc "Manages DSPy sessions using Snakepit's session infrastructure"
  
  def create(opts \\ []) do
    session_id = "dspex_session_#{:erlang.unique_integer([:positive])}"
    
    # Initialize session with DSPy configuration
    with {:ok, _} <- Snakepit.execute_in_session(session_id, "ping", %{}, opts),
         {:ok, _} <- configure_dspy_in_session(session_id, opts) do
      {:ok, session_id}
    end
  end
  
  def execute(session_id, module_id, inputs, opts \\ []) do
    Snakepit.execute_in_session(
      session_id, 
      "call",
      %{target: "stored.#{module_id}", kwargs: inputs},
      opts
    )
  end
end
```

## Implementation Steps

### 1. Update Configuration (Immediate)
- [x] Update config/config.exs to use GRPCPython adapter
- [ ] Remove wire_protocol and other legacy settings
- [ ] Configure proper adapter_args for DSPy

### 2. Refactor Core Modules (High Priority)
- [ ] DSPex.Config - Already uses Snakepit.Python.call correctly
- [ ] DSPex.LM - Update configure/2 to use proper gRPC calls
- [ ] DSPex.Modules.Predict - Use Python.call with store_as
- [ ] DSPex.Modules.ChainOfThought - Similar pattern
- [ ] DSPex.Modules.ReAct - Update for gRPC
- [ ] DSPex.Modules.ProgramOfThought - Update for gRPC

### 3. Update Examples (Medium Priority)
- [ ] Update all examples to remove legacy adapter configuration
- [ ] Use clean Snakepit API patterns
- [ ] Add session management where appropriate

### 4. Remove Legacy Code (Low Priority)
- [ ] Remove priv/python/dspy_bridge.py (replaced by gRPC adapter)
- [ ] Remove DSPex.Python.Bridge if no longer needed
- [ ] Clean up old protocol handling code

## Benefits of This Approach

1. **Simpler Code**: Remove hundreds of lines of bridge code
2. **Better Performance**: gRPC with binary serialization for large data
3. **Reliability**: Leverage Snakepit's battle-tested infrastructure
4. **Features**: Get streaming, tool discovery, and session management for free
5. **Maintainability**: Single bridge implementation to maintain

## Example: Complete Flow

```elixir
# Configure DSPy
{:ok, _} = Snakepit.Python.call("dspy.configure", %{
  lm: "gemini/gemini-2.0-flash-exp",
  api_key: System.get_env("GEMINI_API_KEY")
})

# Create a predictor
{:ok, _} = Snakepit.Python.call("dspy.Predict", 
  %{signature: "question -> answer"}, 
  store_as: "qa_predictor"
)

# Use it
{:ok, result} = Snakepit.Python.call("stored.qa_predictor", %{
  question: "What is the capital of France?"
})

# For stateful workflows, use sessions
{:ok, session_id} = DSPex.Session.create()
{:ok, result} = DSPex.Session.execute(session_id, "qa_predictor", %{
  question: "What is the capital of France?"
})
```

## Timeline

1. **Week 1**: Update configuration and core modules
2. **Week 2**: Refactor all DSPex.Modules.*
3. **Week 3**: Update examples and test
4. **Week 4**: Remove legacy code and update documentation

## Notes

- The gRPC adapter (`dspy_grpc.py`) created earlier can be enhanced as needed
- Consider contributing improvements back to Snakepit
- Focus on using Snakepit's patterns rather than fighting them