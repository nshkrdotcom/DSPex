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

### 4. Contract Definitions (Primary Approach)

Define explicit contracts for each component type:

```elixir
defmodule DSPex.Contracts.Predict do
  use DSPex.Contract
  
  @moduledoc """
  Explicit contract for dspy.Predict.
  This is the source of truth - no runtime discovery needed.
  """
  
  @python_class "dspy.Predict"
  
  defmethod :create, :__init__,
    params: [
      signature: {:required, :string}
    ],
    returns: :reference
    
  defmethod :predict, :__call__,
    params: [
      question: {:required, :string}
    ],
    returns: {:struct, DSPex.Types.Prediction}
    
  defmethod :forward, "forward",
    params: :variable_keyword,
    returns: {:struct, DSPex.Types.Prediction}
    
  @doc """
  Version this contract was created against.
  Update when Python API changes.
  """
  def contract_version, do: "1.0.0"
end
```

### 5. Schema Discovery (Development Tool Only)

Use schema discovery as a development aid, not a runtime dependency:

```bash
# Generate a contract template from Python class
mix dspex.gen.contract dspy.ChainOfThought --output lib/dspex/contracts/chain_of_thought.ex

# Review the generated file and customize
# The generated contract is a starting point, not the final version
```

Generated template example:
```elixir
# GENERATED CONTRACT TEMPLATE - REVIEW AND CUSTOMIZE
defmodule DSPex.Contracts.ChainOfThought do
  use DSPex.Contract
  
  @moduledoc """
  Contract for dspy.ChainOfThought
  Generated on: 2024-01-15
  
  TODO: Review methods and types
  TODO: Add business logic validations
  TODO: Document version compatibility
  """
  
  @python_class "dspy.ChainOfThought"
  
  # Methods discovered from Python...
end
```

## Implementation Examples

### 1. Typed Wrapper Module

```elixir
defmodule MyApp.TypedPredictor do
  use DSPex.Bridge.ContractBased
  
  # Use explicit contract
  use_contract DSPex.Contracts.Predict
  
  defstruct [:ref, :signature]
  
  # Contract generates these typed functions:
  # - create(signature) with compile-time validation
  # - predict(ref, question) with proper types
  # - forward(ref, opts) with keyword validation
  
  # Additional business logic
  def predict_with_context(%__MODULE__{ref: ref}, question, context) do
    # Combine question and context
    enhanced_question = "Context: #{context}\nQuestion: #{question}"
    
    # Use contract-generated function
    predict(ref, question: enhanced_question)
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

## Compile-Time Considerations

### Challenges with Runtime Discovery

Attempting Python introspection at compile time creates several problems:

1. **Build Environment Complexity**
   - CI/CD servers need Python + DSPy installed
   - Version mismatches cause build failures
   - Docker images become bloated

2. **Compilation Performance**
   - Every `mix compile` potentially starts Python
   - Incremental compilation slows dramatically
   - Developer experience degrades

3. **Failure Modes**
   - Network issues fetching Python deps = build fails
   - Python version mismatch = build fails
   - Missing dependencies = build fails

### Solution: Explicit Contracts + Dev Tools

```elixir
# Development workflow
# 1. Developer runs mix task in their environment
mix dspex.gen.contract dspy.NewComponent

# 2. Reviews and customizes generated contract
vim lib/dspex/contracts/new_component.ex

# 3. Commits contract to version control
git add lib/dspex/contracts/new_component.ex
git commit -m "Add contract for dspy.NewComponent"

# 4. CI/CD builds with pure Elixir - no Python needed!
```

### Contract Versioning Strategy

```elixir
defmodule DSPex.Contracts.Predict do
  use DSPex.Contract
  
  # Track compatibility
  @contract_version "1.2.0"
  @compatible_with_dspy "~> 2.1"
  
  # Runtime validation (optional)
  def validate_compatibility(python_version) do
    Version.match?(python_version, @compatible_with_dspy)
  end
end
```

## Migration Strategy

### Phase 1: Define Core Types
1. Create DSPex.Types module hierarchy
2. Define structs for all return types
3. Add from_python_result/1 functions

### Phase 2: Create Contract Infrastructure
1. Implement DSPex.Contract behaviour
2. Create defmethod macro for contracts
3. Add compile-time validation

### Phase 3: Build Development Tools
1. Create mix dspex.gen.contract task
2. Add contract validation helpers
3. Document contract update workflow

### Phase 4: Migrate Existing Code
1. Generate contracts for existing DSPy usage
2. Review and customize each contract
3. Update code to use contract-based approach

### Phase 5: Deprecate String-Based API
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