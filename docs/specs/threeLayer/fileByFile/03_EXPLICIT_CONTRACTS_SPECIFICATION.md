# Explicit Contracts Specification

## Moving from Stringly-Typed to Strongly-Typed

The current bridge relies heavily on string-based method names and untyped maps. This document specifies how to make contracts explicit and type-safe.

## Current Problems

### 1. No Compile-Time Validation
```elixir
# This compiles but fails at runtime if method doesn't exist
Bridge.call_method(ref, "pridict", %{question: "oops"})  # Typo!
```

### 2. No Parameter Validation
```elixir
# This compiles but fails in Python when expecting 'question' not 'query'
Bridge.call_method(ref, "__call__", %{query: "What is AI?"})
```

### 3. Opaque Return Types
```elixir
# What does this return? Who knows!
{:ok, result} = Bridge.call_method(ref, "forward", inputs)
# result could be anything - map, list, string, etc.
```

## Solution: Contract-First Design

### 1. Protocol-Based Contracts

Define explicit protocols for each DSPy component type:

```elixir
defprotocol DSPex.Contracts.Predictor do
  @doc "Initialize a predictor with a signature"
  @spec init(t(), String.t() | map()) :: {:ok, t()} | {:error, term()}
  def init(predictor, signature)
  
  @doc "Execute prediction on inputs"
  @spec predict(t(), map()) :: {:ok, DSPex.Types.Prediction.t()} | {:error, term()}
  def predict(predictor, inputs)
  
  @doc "Get the signature specification"
  @spec signature(t()) :: DSPex.Types.Signature.t()
  def signature(predictor)
end
```

### 2. Typed Domain Models

Replace generic maps with explicit structs:

```elixir
defmodule DSPex.Types.Prediction do
  @type t :: %__MODULE__{
    answer: String.t(),
    confidence: float() | nil,
    reasoning: String.t() | nil,
    metadata: map()
  }
  
  defstruct [:answer, :confidence, :reasoning, metadata: %{}]
  
  @doc "Validate and construct from Python result"
  def from_python_result(%{"answer" => answer} = result) do
    {:ok, %__MODULE__{
      answer: answer,
      confidence: Map.get(result, "confidence"),
      reasoning: Map.get(result, "reasoning"),
      metadata: Map.drop(result, ["answer", "confidence", "reasoning"])
    }}
  end
  
  def from_python_result(_), do: {:error, :invalid_prediction_format}
end
```

### 3. Compile-Time Method Registration

Instead of runtime string lookups, register methods at compile time:

```elixir
defmodule DSPex.Bridge.MethodRegistry do
  @moduledoc """
  Compile-time registry of Python method signatures.
  """
  
  defmacro register_method(name, python_name, params, return_type) do
    quote do
      @methods {unquote(name), %{
        python_name: unquote(python_name),
        params: unquote(params),
        return_type: unquote(return_type)
      }}
      
      def unquote(name)(ref, params) do
        # Validate params at compile time
        validated = DSPex.Validation.validate_params(
          params, 
          unquote(params)
        )
        
        case DSPex.Bridge.call_method(ref, unquote(python_name), validated) do
          {:ok, result} -> 
            DSPex.Validation.cast_result(result, unquote(return_type))
          error -> 
            error
        end
      end
    end
  end
end
```

### 4. Schema Definitions

Define schemas for each component type:

```elixir
defmodule DSPex.Schemas.Predict do
  use DSPex.Schema
  
  @python_class "dspy.Predict"
  
  defmethod :__init__, "__init__",
    params: [
      signature: {:required, :string}
    ],
    returns: :reference
    
  defmethod :__call__, "__call__",
    params: [
      inputs: {:required, :map}
    ],
    returns: {:struct, DSPex.Types.Prediction}
    
  defmethod :forward, "forward",
    params: :variable_keyword,
    returns: {:struct, DSPex.Types.Prediction}
end
```

## Implementation Examples

### 1. Typed Wrapper Module

```elixir
defmodule MyApp.TypedPredictor do
  @behaviour DSPex.Component
  
  use DSPex.Schemas.Predict
  
  defstruct [:ref, :signature]
  
  @impl DSPex.Component
  def create(signature) when is_binary(signature) do
    case __init__(signature) do
      {:ok, ref} ->
        {:ok, %__MODULE__{ref: ref, signature: signature}}
      error ->
        error
    end
  end
  
  @impl DSPex.Component
  def execute(%__MODULE__{ref: ref}, inputs) when is_map(inputs) do
    __call__(ref, inputs)
  end
end
```

### 2. Contract Validation

```elixir
defmodule DSPex.Validation do
  @moduledoc """
  Runtime and compile-time validation of contracts.
  """
  
  def validate_params(params, schema) do
    schema
    |> Enum.reduce_while({:ok, %{}}, fn {key, spec}, {:ok, acc} ->
      case validate_param(params[key], spec) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
  
  defp validate_param(value, {:required, type}) when is_nil(value) do
    {:error, {:missing_required_param, type}}
  end
  
  defp validate_param(value, {:required, type}) do
    validate_type(value, type)
  end
  
  defp validate_param(value, {:optional, type, default}) do
    if is_nil(value) do
      {:ok, default}
    else
      validate_type(value, type)
    end
  end
  
  defp validate_type(value, :string) when is_binary(value), do: {:ok, value}
  defp validate_type(value, :map) when is_map(value), do: {:ok, value}
  defp validate_type(value, :integer) when is_integer(value), do: {:ok, value}
  defp validate_type(value, type), do: {:error, {:invalid_type, type, value}}
end
```

### 3. Result Type Casting

```elixir
defmodule DSPex.TypeCasting do
  @moduledoc """
  Cast Python results to Elixir types.
  """
  
  def cast_result(result, :string) when is_binary(result), do: {:ok, result}
  def cast_result(result, :map) when is_map(result), do: {:ok, result}
  
  def cast_result(result, {:struct, module}) when is_map(result) do
    if function_exported?(module, :from_python_result, 1) do
      module.from_python_result(result)
    else
      struct_from_map(module, result)
    end
  end
  
  def cast_result(result, {:list, type}) when is_list(result) do
    result
    |> Enum.map(&cast_result(&1, type))
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, item}, {:ok, acc} -> {:cont, {:ok, [item | acc]}}
      error, _ -> {:halt, error}
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end
  
  defp struct_from_map(module, map) do
    {:ok, struct(module, map)}
  rescue
    _ -> {:error, {:invalid_struct, module, map}}
  end
end
```

## Contract Examples

### 1. ChainOfThought Contract

```elixir
defmodule DSPex.Contracts.ChainOfThought do
  use DSPex.Schema
  
  @python_class "dspy.ChainOfThought"
  
  defmethod :__init__, "__init__",
    params: [
      signature: {:required, :string},
      rationale_type: {:optional, :string, "simple"}
    ],
    returns: :reference
    
  defmethod :__call__, "__call__",
    params: [
      inputs: {:required, :map}
    ],
    returns: {:struct, DSPex.Types.ChainOfThoughtResult}
    
  defstruct [:reasoning, :answer, :confidence]
end

defmodule DSPex.Types.ChainOfThoughtResult do
  @type t :: %__MODULE__{
    reasoning: [String.t()],
    answer: String.t(),
    confidence: float() | nil
  }
  
  defstruct [:reasoning, :answer, :confidence]
  
  def from_python_result(%{"reasoning" => reasoning, "answer" => answer} = result) do
    {:ok, %__MODULE__{
      reasoning: parse_reasoning_steps(reasoning),
      answer: answer,
      confidence: Map.get(result, "confidence")
    }}
  end
  
  defp parse_reasoning_steps(reasoning) when is_binary(reasoning) do
    reasoning
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
  
  defp parse_reasoning_steps(steps) when is_list(steps), do: steps
end
```

### 2. Retrieve Contract

```elixir
defmodule DSPex.Contracts.Retrieve do
  use DSPex.Schema
  
  @python_class "dspy.Retrieve"
  
  defmethod :__init__, "__init__",
    params: [
      k: {:optional, :integer, 3}
    ],
    returns: :reference
    
  defmethod :__call__, "__call__",
    params: [
      query: {:required, :string}
    ],
    returns: {:list, {:struct, DSPex.Types.Passage}}
end

defmodule DSPex.Types.Passage do
  @type t :: %__MODULE__{
    text: String.t(),
    score: float(),
    metadata: map()
  }
  
  defstruct [:text, :score, metadata: %{}]
end
```

## Benefits of Explicit Contracts

### 1. Compile-Time Safety
- Method names are validated at compile time
- Parameter names and types are checked
- Return types are guaranteed

### 2. Better Developer Experience
- Auto-completion works
- Documentation is accurate
- Errors are clear and actionable

### 3. Easier Testing
```elixir
# Can mock at the contract level
defmodule MockPredictor do
  @behaviour DSPex.Contracts.Predictor
  
  def init(_predictor, _signature), do: {:ok, %{}}
  def predict(_predictor, %{question: "test"}), do: {:ok, %DSPex.Types.Prediction{answer: "mocked"}}
  def signature(_predictor), do: %DSPex.Types.Signature{inputs: ["question"], outputs: ["answer"]}
end
```

### 4. Runtime Validation
```elixir
# Contracts can validate at runtime too
case DSPex.Contracts.validate_prediction(result) do
  {:ok, prediction} -> process(prediction)
  {:error, violations} -> handle_invalid_result(violations)
end
```

## Migration Strategy

### Phase 1: Define Core Types
1. Create DSPex.Types module hierarchy
2. Define structs for all return types
3. Add from_python_result/1 functions

### Phase 2: Create Schema DSL
1. Implement DSPex.Schema behaviour
2. Create defmethod macro
3. Add validation infrastructure

### Phase 3: Generate Contracts
1. For each DSPy class, create a contract module
2. Use schema introspection to generate automatically
3. Allow manual overrides for complex cases

### Phase 4: Deprecate String-Based API
1. Mark Bridge.call_method/3 as deprecated
2. Provide migration guide
3. Remove in next major version

## Summary

By moving from stringly-typed to strongly-typed contracts:
1. **Safety**: Catch errors at compile time
2. **Clarity**: Know exactly what methods expect and return
3. **Tooling**: Better IDE support and documentation
4. **Testing**: Easier to mock and test

The investment in explicit contracts pays dividends in maintainability and developer happiness.