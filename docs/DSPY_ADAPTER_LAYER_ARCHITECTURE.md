# DSPy Adapter Layer Architecture

## Overview

This document defines the adapter layer that sits between the Ash resources and the actual DSPy implementation. This layer provides a stable contract that allows seamless switching between a Python ports implementation and a future native Elixir implementation (DSPEx).

## Architecture Principles

1. **Implementation Agnostic**: The adapter interface must not leak implementation details
2. **DSPy Semantics**: The interface must faithfully represent DSPy's core abstractions
3. **Stateless Operations**: Each operation should be independent (state lives in Ash)
4. **Type Safety**: Use Elixir structs and typespecs for all data exchange
5. **Error Boundaries**: Clear error types that work for both implementations

## Layer Structure

```
MyApp
├── lib/
│   ├── my_app/
│   │   ├── ml/                    # Ash Domain & Resources
│   │   │   ├── program.ex
│   │   │   ├── module.ex
│   │   │   └── ...
│   │   │
│   │   ├── ml_data_layer.ex      # Ash Data Layer (uses adapter)
│   │   │
│   │   └── dspy/                  # DSPy Adapter Layer
│   │       ├── adapter.ex         # Behaviour definition
│   │       ├── types.ex           # Shared type definitions
│   │       ├── errors.ex          # Error types
│   │       │
│   │       ├── adapters/
│   │       │   ├── python_port.ex # Python implementation
│   │       │   └── native.ex      # Future Elixir implementation
│   │       │
│   │       └── python_port/       # Python-specific modules
│   │           ├── bridge.ex      # Port management
│   │           ├── protocol.ex    # Wire protocol
│   │           └── state.ex       # Python state cache
```

## Core Adapter Behaviour

```elixir
defmodule MyApp.DSPy.Adapter do
  @moduledoc """
  Behaviour defining the DSPy adapter interface.
  
  Implementations must provide all DSPy core operations while
  maintaining implementation independence.
  """
  
  alias MyApp.DSPy.Types.{
    Program,
    Module,
    Signature,
    Example,
    ExecutionResult,
    CompilationResult,
    Configuration
  }
  
  @doc "Initialize the adapter with configuration"
  @callback initialize(config :: map()) :: {:ok, state :: term()} | {:error, term()}
  
  @doc "Configure global DSPy settings (LM, RM, adapter)"
  @callback configure(Configuration.t(), state :: term()) :: 
    {:ok, state :: term()} | {:error, term()}
  
  # Program Management
  @callback create_program(Program.t(), state :: term()) :: 
    {:ok, program_id :: String.t(), state :: term()} | {:error, term()}
    
  @callback get_program(program_id :: String.t(), state :: term()) ::
    {:ok, Program.t(), state :: term()} | {:error, term()}
    
  @callback delete_program(program_id :: String.t(), state :: term()) ::
    {:ok, state :: term()} | {:error, term()}
  
  # Execution
  @callback execute(program_id :: String.t(), input :: map(), state :: term()) ::
    {:ok, ExecutionResult.t(), state :: term()} | {:error, term()}
    
  @callback execute_module(
    module :: Module.t(), 
    input :: map(), 
    context :: map(),
    state :: term()
  ) :: {:ok, map(), state :: term()} | {:error, term()}
  
  # Compilation / Optimization
  @callback compile(
    program_id :: String.t(),
    optimizer :: atom(),
    optimizer_config :: map(),
    trainset :: [Example.t()],
    metric :: String.t() | fun(),
    state :: term()
  ) :: {:ok, CompilationResult.t(), state :: term()} | {:error, term()}
  
  # Evaluation
  @callback evaluate(
    program_id :: String.t(),
    examples :: [Example.t()],
    metric :: String.t() | fun(),
    state :: term()
  ) :: {:ok, %{score: float(), results: list()}, state :: term()} | {:error, term()}
  
  # Utility
  @callback list_available_modules(state :: term()) :: 
    {:ok, [module_info :: map()], state :: term()}
    
  @callback list_available_metrics(state :: term()) ::
    {:ok, [metric_info :: map()], state :: term()}
    
  @callback validate_signature(signature :: String.t(), state :: term()) ::
    {:ok, Signature.t(), state :: term()} | {:error, term()}
end
```

## Type Definitions

```elixir
defmodule MyApp.DSPy.Types do
  @moduledoc "Shared type definitions for DSPy operations"
  
  defmodule Signature do
    @enforce_keys [:raw, :inputs, :outputs]
    defstruct [:raw, :inputs, :outputs]
    
    @type field :: %{name: String.t(), description: String.t() | nil, prefix: String.t() | nil}
    @type t :: %__MODULE__{
      raw: String.t(),
      inputs: [field()],
      outputs: [field()]
    }
  end
  
  defmodule Module do
    @enforce_keys [:id, :type, :config]
    defstruct [:id, :type, :config, :signature, :metadata]
    
    @type module_type :: :predict | :chain_of_thought | :retrieve | :react | :custom
    @type t :: %__MODULE__{
      id: String.t(),
      type: module_type(),
      config: map(),
      signature: Signature.t() | nil,
      metadata: map()
    }
  end
  
  defmodule Program do
    @enforce_keys [:id, :modules, :forward]
    defstruct [:id, :modules, :forward, :metadata]
    
    @type forward_op :: 
      {:call, module_id :: String.t(), args :: map(), save_as :: String.t()} |
      {:map, module_id :: String.t(), over :: String.t(), save_as :: String.t()} |
      {:set, var :: String.t(), value :: term()} |
      {:return, value :: map()}
      
    @type t :: %__MODULE__{
      id: String.t(),
      modules: %{String.t() => Module.t()},
      forward: [forward_op()],
      metadata: map()
    }
  end
  
  defmodule Example do
    @enforce_keys [:inputs]
    defstruct [:inputs, :outputs, :metadata]
    
    @type t :: %__MODULE__{
      inputs: map(),
      outputs: map() | nil,
      metadata: map()
    }
  end
  
  defmodule ExecutionResult do
    @enforce_keys [:output, :trace, :metrics]
    defstruct [:output, :trace, :metrics, :error]
    
    @type trace_entry :: %{
      module_id: String.t(),
      input: map(),
      output: map(),
      duration_ms: integer(),
      metadata: map()
    }
    
    @type t :: %__MODULE__{
      output: map(),
      trace: [trace_entry()],
      metrics: %{
        total_duration_ms: integer(),
        token_usage: map(),
        calls: integer()
      },
      error: String.t() | nil
    }
  end
  
  defmodule CompilationResult do
    @enforce_keys [:program_id, :score, :optimized_program]
    defstruct [:program_id, :score, :optimized_program, :metadata]
    
    @type t :: %__MODULE__{
      program_id: String.t(),
      score: float(),
      optimized_program: Program.t(),
      metadata: map()
    }
  end
  
  defmodule Configuration do
    @enforce_keys []
    defstruct [:lm, :rm, :adapter]
    
    @type lm_config :: %{
      provider: String.t(),
      model: String.t(),
      api_key: String.t(),
      optional(:temperature) => float(),
      optional(:max_tokens) => integer()
    }
    
    @type rm_config :: %{
      provider: String.t(),
      optional(:url) => String.t(),
      optional(:api_key) => String.t()
    }
    
    @type t :: %__MODULE__{
      lm: lm_config() | nil,
      rm: rm_config() | nil,
      adapter: String.t() | nil
    }
  end
end
```

## Python Port Adapter Implementation

```elixir
defmodule MyApp.DSPy.Adapters.PythonPort do
  @behaviour MyApp.DSPy.Adapter
  
  alias MyApp.DSPy.PythonPort.{Bridge, Protocol}
  alias MyApp.DSPy.Types
  
  defstruct [:bridge_pid, :config]
  
  @impl true
  def initialize(config) do
    case Bridge.start_link(config) do
      {:ok, pid} -> {:ok, %__MODULE__{bridge_pid: pid, config: config}}
      error -> error
    end
  end
  
  @impl true
  def configure(%Types.Configuration{} = config, %__MODULE__{} = state) do
    request = Protocol.encode_request(:configure, %{
      lm: config.lm,
      rm: config.rm,
      adapter: config.adapter
    })
    
    case Bridge.call(state.bridge_pid, request) do
      {:ok, _response} -> {:ok, state}
      error -> error
    end
  end
  
  @impl true
  def create_program(%Types.Program{} = program, %__MODULE__{} = state) do
    # Convert Elixir program representation to Python-friendly format
    py_program = %{
      "__type__" => "program",
      "__id__" => program.id,
      "modules" => encode_modules(program.modules),
      "forward" => encode_forward_ops(program.forward)
    }
    
    request = Protocol.encode_request(:define_program, py_program)
    
    case Bridge.call(state.bridge_pid, request) do
      {:ok, %{"program_id" => id}} -> {:ok, id, state}
      error -> error
    end
  end
  
  @impl true
  def execute(program_id, input, %__MODULE__{} = state) do
    request = Protocol.encode_request(:run, %{
      program_id: program_id,
      input: input
    })
    
    case Bridge.call(state.bridge_pid, request) do
      {:ok, response} -> 
        result = decode_execution_result(response)
        {:ok, result, state}
      error -> 
        error
    end
  end
  
  # ... other callback implementations
  
  # Helper functions for encoding/decoding
  defp encode_modules(modules) do
    Map.new(modules, fn {id, module} ->
      {id, encode_module(module)}
    end)
  end
  
  defp encode_module(%Types.Module{} = module) do
    base = %{
      "__type__" => "module",
      "name" => module_type_to_dspy_class(module.type),
      "args" => module.config
    }
    
    if module.signature do
      Map.put(base, "args", Map.put(module.config, "signature", module.signature.raw))
    else
      base
    end
  end
  
  defp module_type_to_dspy_class(type) do
    case type do
      :predict -> "Predict"
      :chain_of_thought -> "ChainOfThought"
      :retrieve -> "Retrieve"
      :react -> "ReAct"
      :custom -> raise "Custom modules require explicit class name"
    end
  end
  
  defp encode_forward_ops(ops) do
    Enum.map(ops, fn
      {:call, module_id, args, save_as} ->
        %{"op" => "call", "module" => module_id, "args" => args, "save_as" => save_as}
      
      {:map, module_id, over, save_as} ->
        %{"op" => "map", "module" => module_id, "over" => over, "save_as" => save_as}
        
      {:set, var, value} ->
        %{"op" => "set", "var" => var, "value" => value}
        
      {:return, value} ->
        %{"op" => "return", "value" => value}
    end)
  end
  
  defp decode_execution_result(response) do
    %Types.ExecutionResult{
      output: response["output"],
      trace: decode_trace(response["trace"]),
      metrics: %{
        total_duration_ms: response["duration_ms"],
        token_usage: response["token_usage"],
        calls: length(response["trace"])
      }
    }
  end
  
  defp decode_trace(trace_data) do
    Enum.map(trace_data, fn entry ->
      %{
        module_id: entry["module_id"],
        input: entry["input"],
        output: entry["output"],
        duration_ms: entry["duration_ms"],
        metadata: entry["metadata"] || %{}
      }
    end)
  end
end
```

## Bridge Protocol

```elixir
defmodule MyApp.DSPy.PythonPort.Protocol do
  @moduledoc "Wire protocol for Python communication"
  
  @protocol_version "1.0"
  
  def encode_request(command, payload) do
    %{
      version: @protocol_version,
      id: generate_request_id(),
      command: to_string(command),
      payload: payload,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> Jason.encode!()
  end
  
  def decode_response(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"success" => true, "data" => data}} ->
        {:ok, data}
      
      {:ok, %{"success" => false, "error" => error}} ->
        {:error, decode_error(error)}
        
      {:error, _} = error ->
        error
    end
  end
  
  defp decode_error(%{"type" => type, "message" => message, "details" => details}) do
    %MyApp.DSPy.Error{
      type: String.to_existing_atom(type),
      message: message,
      details: details
    }
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
```

## Native Adapter Stub

```elixir
defmodule MyApp.DSPy.Adapters.Native do
  @moduledoc """
  Native Elixir implementation of DSPy.
  
  This is a stub that will be implemented as DSPEx matures.
  """
  
  @behaviour MyApp.DSPy.Adapter
  
  # This will eventually be the pure Elixir implementation
  # For now, it's a stub that shows the interface contract
  
  @impl true
  def initialize(_config) do
    {:error, :not_implemented}
  end
  
  # ... other stubs
end
```

## Integration with Ash Data Layer

```elixir
defmodule MyApp.MLDataLayer do
  @behaviour Ash.DataLayer
  
  # Configuration to select adapter
  @adapter Application.compile_env(:my_app, :dspy_adapter, MyApp.DSPy.Adapters.PythonPort)
  
  def init(_opts) do
    {:ok, %{adapter: @adapter, adapter_state: nil}}
  end
  
  def layer_init(resource, %{adapter: adapter} = state) do
    config = Application.get_env(:my_app, :dspy_config, %{})
    
    case adapter.initialize(config) do
      {:ok, adapter_state} ->
        {:ok, %{state | adapter_state: adapter_state}}
      error ->
        error
    end
  end
  
  def run_query(query, _resource, %{adapter: adapter, adapter_state: adapter_state} = state) do
    case query.action.name do
      :execute ->
        [%{program_id: program_id, input: input}] = query.arguments
        
        case adapter.execute(program_id, input, adapter_state) do
          {:ok, result, new_adapter_state} ->
            # Convert to Ash result format
            ash_result = execution_result_to_ash(result)
            {:ok, [ash_result], %{state | adapter_state: new_adapter_state}}
            
          {:error, error} ->
            {:error, error}
        end
        
      :compile ->
        # Similar pattern for compilation
        
      _ ->
        # Delegate to Postgres for standard CRUD operations
        AshPostgres.DataLayer.run_query(query, resource, state)
    end
  end
  
  defp execution_result_to_ash(%Types.ExecutionResult{} = result) do
    %{
      output: result.output,
      trace: result.trace,
      duration_ms: result.metrics.total_duration_ms,
      token_usage: result.metrics.token_usage,
      state: :completed
    }
  end
end
```

## Configuration

```elixir
# config/config.exs
config :my_app, :dspy_adapter, MyApp.DSPy.Adapters.PythonPort

config :my_app, :dspy_config, %{
  python_path: "python3",
  bridge_script: "priv/python/dspy_bridge.py",
  pool_size: 4,
  max_queue: 100
}

# Future: Switch to native implementation
# config :my_app, :dspy_adapter, MyApp.DSPy.Adapters.Native
```

## Testing Strategy

```elixir
defmodule MyApp.DSPy.AdapterTest do
  use ExUnit.Case
  
  # Shared test suite that all adapters must pass
  defmodule SharedTests do
    defmacro __using__(adapter: adapter) do
      quote do
        @adapter unquote(adapter)
        
        setup do
          {:ok, state} = @adapter.initialize(%{})
          {:ok, adapter_state: state}
        end
        
        test "creates and executes a simple program", %{adapter_state: state} do
          program = %Types.Program{
            id: "test_program",
            modules: %{
              "generator" => %Types.Module{
                id: "generator",
                type: :predict,
                signature: %Types.Signature{
                  raw: "question -> answer",
                  inputs: [%{name: "question"}],
                  outputs: [%{name: "answer"}]
                },
                config: %{}
              }
            },
            forward: [
              {:call, "generator", %{"question" => "question"}, "result"},
              {:return, %{"answer" => "result.answer"}}
            ]
          }
          
          assert {:ok, "test_program", state} = @adapter.create_program(program, state)
          
          input = %{"question" => "What is DSPy?"}
          assert {:ok, result, _state} = @adapter.execute("test_program", input, state)
          assert %Types.ExecutionResult{} = result
          assert Map.has_key?(result.output, "answer")
        end
        
        # More shared tests...
      end
    end
  end
end

# Test each adapter with the same test suite
defmodule MyApp.DSPy.Adapters.PythonPortTest do
  use MyApp.DSPy.AdapterTest.SharedTests, adapter: MyApp.DSPy.Adapters.PythonPort
end

defmodule MyApp.DSPy.Adapters.NativeTest do
  use MyApp.DSPy.AdapterTest.SharedTests, adapter: MyApp.DSPy.Adapters.Native
  
  @tag :skip  # Until native implementation exists
  test "placeholder" do
    :ok
  end
end
```

## Benefits of This Architecture

1. **Clean Separation**: The adapter interface is purely about DSPy semantics, not implementation details
2. **Type Safety**: All data exchange uses well-defined Elixir structs
3. **Testability**: Shared test suite ensures compatibility between implementations
4. **Migration Path**: Can gradually implement native modules while using Python for others
5. **Performance**: Can optimize hot paths in native implementation while keeping Python for complex operations
6. **Debugging**: Clear boundaries make it easy to trace issues

## Implementation Roadmap

### Phase 1: Python Port Adapter (Weeks 1-2)
- Complete protocol implementation
- Bridge process with supervision
- Error handling and recovery
- Integration tests

### Phase 2: Hybrid Support (Weeks 3-4)
- Module-level adapter selection
- Performance profiling
- Caching layer for embeddings

### Phase 3: Native Implementation (Months 2-6)
- Start with simple modules (Predict)
- Implement signature parsing
- Port evaluation metrics
- Graduate to complex modules (ChainOfThought, ReAct)

### Phase 4: Optimization (Ongoing)
- Native implementations of hot paths
- Specialized data structures
- GPU acceleration support
