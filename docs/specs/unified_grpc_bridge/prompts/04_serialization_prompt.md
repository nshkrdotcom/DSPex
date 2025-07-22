# Prompt: Implement Type Serialization System

## Objective
Implement a comprehensive type serialization system that handles all variable types using protobuf Any with JSON encoding, ensuring type safety and cross-language compatibility.

## Context
The serialization system is critical for maintaining type safety across the Elixir-Python boundary. We use protobuf Any with JSON payloads for flexibility while maintaining strong typing.

## Requirements

### Type System Support
Implement serialization/deserialization for:
1. **Basic Types**: float, integer, string, boolean
2. **Enumeration Type**: choice (with allowed values)
3. **Reference Type**: module (DSPy module names)
4. **Numeric Types**: embedding (vectors), tensor (multi-dimensional)
5. **Future Types**: Leave extensible for custom types

### Cross-Language Consistency
- Same serialization logic in both Elixir and Python
- Handle edge cases (NaN, Infinity, null/nil)
- Preserve precision for numeric types
- Support nested structures

## Implementation Steps

### 1. Create Elixir Type System

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types.ex

defmodule Snakepit.Bridge.Variables.Types do
  @moduledoc """
  Type system for bridge variables with serialization support.
  """
  
  @type var_type :: :float | :integer | :string | :boolean | 
                    :choice | :module | :embedding | :tensor
  
  @doc """
  Get the type module for a given type atom.
  """
  def get_type_module(:float), do: {:ok, __MODULE__.Float}
  def get_type_module(:integer), do: {:ok, __MODULE__.Integer}
  def get_type_module(:string), do: {:ok, __MODULE__.String}
  def get_type_module(:boolean), do: {:ok, __MODULE__.Boolean}
  def get_type_module(:choice), do: {:ok, __MODULE__.Choice}
  def get_type_module(:module), do: {:ok, __MODULE__.Module}
  def get_type_module(:embedding), do: {:ok, __MODULE__.Embedding}
  def get_type_module(:tensor), do: {:ok, __MODULE__.Tensor}
  def get_type_module(_), do: {:error, :unknown_type}
  
  @doc """
  Common behaviour for all types.
  """
  defmodule Behaviour do
    @callback validate(value :: any()) :: {:ok, normalized :: any()} | {:error, reason :: String.t()}
    @callback validate_constraints(value :: any(), constraints :: map()) :: :ok | {:error, reason :: String.t()}
    @callback serialize(value :: any()) :: {:ok, json :: String.t()} | {:error, reason :: String.t()}
    @callback deserialize(json :: String.t()) :: {:ok, value :: any()} | {:error, reason :: String.t()}
  end
end
```

### 2. Implement Basic Types

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types/float.ex

defmodule Snakepit.Bridge.Variables.Types.Float do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_float(value), do: {:ok, value}
  def validate(value) when is_integer(value), do: {:ok, value * 1.0}
  def validate(_), do: {:error, "must be a number"}
  
  @impl true
  def validate_constraints(value, constraints) do
    min = Map.get(constraints, :min, :negative_infinity)
    max = Map.get(constraints, :max, :infinity)
    
    cond do
      min != :negative_infinity and value < min ->
        {:error, "must be >= #{min}"}
      max != :infinity and value > max ->
        {:error, "must be <= #{max}"}
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(value) do
    # Handle special float values
    json_value = cond do
      is_nan(value) -> "NaN"
      value == :infinity -> "Infinity"
      value == :negative_infinity -> "-Infinity"
      true -> value
    end
    
    {:ok, Jason.encode!(json_value)}
  end
  
  @impl true
  def deserialize(json) do
    case Jason.decode(json) do
      {:ok, "NaN"} -> {:ok, :nan}
      {:ok, "Infinity"} -> {:ok, :infinity}
      {:ok, "-Infinity"} -> {:ok, :negative_infinity}
      {:ok, value} when is_number(value) -> {:ok, value * 1.0}
      _ -> {:error, "invalid float format"}
    end
  end
  
  defp is_nan(value) do
    # Elixir doesn't have NaN, but we support it for Python interop
    false
  end
end

# File: snakepit/lib/snakepit/bridge/variables/types/integer.ex

defmodule Snakepit.Bridge.Variables.Types.Integer do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_integer(value), do: {:ok, value}
  def validate(value) when is_float(value) do
    if Float.floor(value) == value do
      {:ok, trunc(value)}
    else
      {:error, "must be a whole number"}
    end
  end
  def validate(_), do: {:error, "must be an integer"}
  
  @impl true
  def validate_constraints(value, constraints) do
    min = Map.get(constraints, :min)
    max = Map.get(constraints, :max)
    
    cond do
      min && value < min -> {:error, "must be >= #{min}"}
      max && value > max -> {:error, "must be <= #{max}"}
      true -> :ok
    end
  end
  
  @impl true
  def serialize(value) do
    {:ok, Jason.encode!(value)}
  end
  
  @impl true
  def deserialize(json) do
    case Jason.decode(json) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      {:ok, value} when is_float(value) and Float.floor(value) == value -> 
        {:ok, trunc(value)}
      _ -> {:error, "invalid integer format"}
    end
  end
end

# File: snakepit/lib/snakepit/bridge/variables/types/string.ex

defmodule Snakepit.Bridge.Variables.Types.String do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_binary(value), do: {:ok, value}
  def validate(value) when is_atom(value), do: {:ok, to_string(value)}
  def validate(_), do: {:error, "must be a string"}
  
  @impl true
  def validate_constraints(value, constraints) do
    min_length = Map.get(constraints, :min_length, 0)
    max_length = Map.get(constraints, :max_length)
    pattern = Map.get(constraints, :pattern)
    
    length = String.length(value)
    
    cond do
      length < min_length ->
        {:error, "must be at least #{min_length} characters"}
      max_length && length > max_length ->
        {:error, "must be at most #{max_length} characters"}
      pattern && not Regex.match?(~r/#{pattern}/, value) ->
        {:error, "must match pattern: #{pattern}"}
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(value) do
    {:ok, Jason.encode!(value)}
  end
  
  @impl true
  def deserialize(json) do
    case Jason.decode(json) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> {:error, "invalid string format"}
    end
  end
end

# File: snakepit/lib/snakepit/bridge/variables/types/boolean.ex

defmodule Snakepit.Bridge.Variables.Types.Boolean do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_boolean(value), do: {:ok, value}
  def validate(_), do: {:error, "must be a boolean"}
  
  @impl true
  def validate_constraints(_value, _constraints), do: :ok
  
  @impl true
  def serialize(value) do
    {:ok, Jason.encode!(value)}
  end
  
  @impl true
  def deserialize(json) do
    case Jason.decode(json) do
      {:ok, value} when is_boolean(value) -> {:ok, value}
      _ -> {:error, "invalid boolean format"}
    end
  end
end
```

### 3. Implement Complex Types

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types/embedding.ex

defmodule Snakepit.Bridge.Variables.Types.Embedding do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(value) when is_list(value) do
    if Enum.all?(value, &is_number/1) do
      {:ok, Enum.map(value, &(&1 * 1.0))}  # Normalize to floats
    else
      {:error, "must be a list of numbers"}
    end
  end
  def validate(_), do: {:error, "must be a numeric list"}
  
  @impl true
  def validate_constraints(value, constraints) do
    dimensions = Map.get(constraints, :dimensions)
    
    if dimensions && length(value) != dimensions do
      {:error, "must have exactly #{dimensions} dimensions"}
    else
      :ok
    end
  end
  
  @impl true
  def serialize(value) do
    {:ok, Jason.encode!(value)}
  end
  
  @impl true
  def deserialize(json) do
    case Jason.decode(json) do
      {:ok, value} when is_list(value) ->
        if Enum.all?(value, &is_number/1) do
          {:ok, Enum.map(value, &(&1 * 1.0))}
        else
          {:error, "invalid embedding format"}
        end
      _ ->
        {:error, "invalid embedding format"}
    end
  end
end

# File: snakepit/lib/snakepit/bridge/variables/types/tensor.ex

defmodule Snakepit.Bridge.Variables.Types.Tensor do
  @behaviour Snakepit.Bridge.Variables.Types.Behaviour
  
  @impl true
  def validate(%{"shape" => shape, "data" => data} = value) 
      when is_list(shape) and is_list(data) do
    expected_size = Enum.reduce(shape, 1, &(&1 * &2))
    actual_size = length(List.flatten(data))
    
    if expected_size == actual_size do
      {:ok, value}
    else
      {:error, "data size doesn't match shape"}
    end
  end
  def validate(_), do: {:error, "must be a tensor with shape and data"}
  
  @impl true
  def validate_constraints(value, constraints) do
    expected_shape = Map.get(constraints, :shape)
    
    if expected_shape && value["shape"] != expected_shape do
      {:error, "shape must be #{inspect(expected_shape)}"}
    else
      :ok
    end
  end
  
  @impl true
  def serialize(value) do
    {:ok, Jason.encode!(value)}
  end
  
  @impl true
  def deserialize(json) do
    case Jason.decode(json) do
      {:ok, %{"shape" => shape, "data" => data}} = result ->
        result
      _ ->
        {:error, "invalid tensor format"}
    end
  end
end
```

### 4. Create Serialization Module

```elixir
# File: snakepit/lib/snakepit/bridge/serialization.ex

defmodule Snakepit.Bridge.Serialization do
  @moduledoc """
  Centralized serialization for the bridge protocol.
  """
  
  alias Snakepit.Bridge.Variables.Types
  
  @doc """
  Encode a value to protobuf Any with JSON payload.
  """
  def encode_any(value, type) do
    with {:ok, type_module} <- Types.get_type_module(type),
         {:ok, normalized} <- type_module.validate(value),
         {:ok, json} <- type_module.serialize(normalized) do
      
      any = Google.Protobuf.Any.new(
        type_url: "dspex.variables/#{type}",
        value: json
      )
      
      {:ok, any}
    end
  end
  
  @doc """
  Decode a protobuf Any to a typed value.
  """
  def decode_any(%Google.Protobuf.Any{} = any) do
    # Extract type from URL
    type = extract_type_from_url(any.type_url)
    
    with {:ok, type_atom} <- parse_type(type),
         {:ok, type_module} <- Types.get_type_module(type_atom),
         {:ok, value} <- type_module.deserialize(any.value) do
      {:ok, value}
    end
  end
  
  @doc """
  Validate a value against type constraints.
  """
  def validate_constraints(value, type, constraints) do
    with {:ok, type_module} <- Types.get_type_module(type) do
      type_module.validate_constraints(value, constraints)
    end
  end
  
  defp extract_type_from_url(type_url) do
    case String.split(type_url, "/") do
      [_prefix, type] -> type
      _ -> nil
    end
  end
  
  defp parse_type("float"), do: {:ok, :float}
  defp parse_type("integer"), do: {:ok, :integer}
  defp parse_type("string"), do: {:ok, :string}
  defp parse_type("boolean"), do: {:ok, :boolean}
  defp parse_type("choice"), do: {:ok, :choice}
  defp parse_type("module"), do: {:ok, :module}
  defp parse_type("embedding"), do: {:ok, :embedding}
  defp parse_type("tensor"), do: {:ok, :tensor}
  defp parse_type(_), do: {:error, :unknown_type}
end
```

### 5. Create Python Serialization

```python
# File: snakepit/priv/python/snakepit_bridge/serialization.py

import json
import numpy as np
from typing import Any, Dict, Union
from google.protobuf import any_pb2

class TypeSerializer:
    """Unified type serialization for Python side."""
    
    @staticmethod
    def encode_any(value: Any, var_type: str) -> any_pb2.Any:
        """Encode a Python value to protobuf Any."""
        # Normalize value based on type
        normalized = TypeSerializer._normalize_value(value, var_type)
        
        # Serialize to JSON
        json_str = TypeSerializer._serialize_value(normalized, var_type)
        
        # Create Any message
        any_msg = any_pb2.Any()
        any_msg.type_url = f"dspex.variables/{var_type}"
        any_msg.value = json_str.encode('utf-8')
        
        return any_msg
    
    @staticmethod
    def decode_any(any_msg: any_pb2.Any) -> Any:
        """Decode protobuf Any to Python value."""
        # Extract type from URL
        var_type = any_msg.type_url.split('/')[-1]
        
        # Decode JSON
        json_str = any_msg.value.decode('utf-8')
        value = json.loads(json_str)
        
        # Convert to appropriate Python type
        return TypeSerializer._deserialize_value(value, var_type)
    
    @staticmethod
    def _normalize_value(value: Any, var_type: str) -> Any:
        """Normalize Python values for consistency."""
        if var_type == 'float':
            if isinstance(value, (int, float)):
                return float(value)
            raise ValueError(f"Expected number, got {type(value)}")
            
        elif var_type == 'integer':
            if isinstance(value, (int, float)):
                if isinstance(value, float) and value.is_integer():
                    return int(value)
                elif isinstance(value, int):
                    return value
            raise ValueError(f"Expected integer, got {value}")
            
        elif var_type == 'string':
            return str(value)
            
        elif var_type == 'boolean':
            if isinstance(value, bool):
                return value
            raise ValueError(f"Expected boolean, got {type(value)}")
            
        elif var_type == 'embedding':
            if isinstance(value, np.ndarray):
                return value.tolist()
            elif isinstance(value, list):
                return [float(x) for x in value]
            raise ValueError(f"Expected array/list, got {type(value)}")
            
        elif var_type == 'tensor':
            if isinstance(value, np.ndarray):
                return {
                    'shape': list(value.shape),
                    'data': value.tolist()
                }
            elif isinstance(value, dict) and 'shape' in value and 'data' in value:
                return value
            raise ValueError(f"Expected tensor, got {type(value)}")
            
        else:
            return value
    
    @staticmethod
    def _serialize_value(value: Any, var_type: str) -> str:
        """Serialize normalized value to JSON string."""
        # Handle special float values
        if var_type == 'float':
            if np.isnan(value):
                return json.dumps("NaN")
            elif np.isinf(value):
                return json.dumps("Infinity" if value > 0 else "-Infinity")
        
        return json.dumps(value)
    
    @staticmethod
    def _deserialize_value(value: Any, var_type: str) -> Any:
        """Convert JSON-decoded value to appropriate Python type."""
        if var_type == 'float':
            if value == "NaN":
                return float('nan')
            elif value == "Infinity":
                return float('inf')
            elif value == "-Infinity":
                return float('-inf')
            return float(value)
            
        elif var_type == 'integer':
            return int(value)
            
        elif var_type == 'embedding':
            # Could convert back to numpy array
            return value
            
        elif var_type == 'tensor':
            # Could reconstruct numpy array
            if isinstance(value, dict) and 'data' in value and 'shape' in value:
                data = np.array(value['data'])
                return data.reshape(value['shape'])
            return value
            
        else:
            return value
    
    @staticmethod
    def validate_constraints(value: Any, var_type: str, constraints: Dict) -> None:
        """Validate value against type constraints."""
        if var_type == 'float' or var_type == 'integer':
            min_val = constraints.get('min')
            max_val = constraints.get('max')
            if min_val is not None and value < min_val:
                raise ValueError(f"Value {value} is below minimum {min_val}")
            if max_val is not None and value > max_val:
                raise ValueError(f"Value {value} is above maximum {max_val}")
                
        elif var_type == 'string':
            min_len = constraints.get('min_length', 0)
            max_len = constraints.get('max_length')
            length = len(value)
            if length < min_len:
                raise ValueError(f"String too short: {length} < {min_len}")
            if max_len and length > max_len:
                raise ValueError(f"String too long: {length} > {max_len}")
                
        elif var_type == 'choice':
            choices = constraints.get('choices', [])
            if choices and value not in choices:
                raise ValueError(f"Value {value} not in allowed choices: {choices}")
                
        elif var_type == 'embedding':
            dimensions = constraints.get('dimensions')
            if dimensions and len(value) != dimensions:
                raise ValueError(f"Wrong dimensions: {len(value)} != {dimensions}")
```

## Testing Strategy

### 1. Unit Tests for Each Type
```elixir
# Test serialization round-trip
test "float serialization" do
  value = 3.14
  {:ok, any} = Serialization.encode_any(value, :float)
  {:ok, decoded} = Serialization.decode_any(any)
  assert decoded == value
end

# Test edge cases
test "special float values" do
  for value <- [:infinity, :negative_infinity] do
    {:ok, any} = Serialization.encode_any(value, :float)
    {:ok, decoded} = Serialization.decode_any(any)
    assert decoded == value
  end
end
```

### 2. Cross-Language Tests
- Serialize in Elixir, deserialize in Python
- Serialize in Python, deserialize in Elixir
- Verify identical JSON representation

### 3. Constraint Validation Tests
```elixir
test "numeric constraints" do
  constraints = %{min: 0, max: 1}
  assert :ok = Serialization.validate_constraints(0.5, :float, constraints)
  assert {:error, _} = Serialization.validate_constraints(1.5, :float, constraints)
end
```

## Files to Create/Modify

1. Create: `snakepit/lib/snakepit/bridge/variables/types.ex`
2. Create: `snakepit/lib/snakepit/bridge/variables/types/*.ex` (one per type)
3. Create: `snakepit/lib/snakepit/bridge/serialization.ex`
4. Create: `snakepit/priv/python/snakepit_bridge/serialization.py`
5. Create: `test/snakepit/bridge/serialization_test.exs`
6. Create: `snakepit/priv/python/tests/test_serialization.py`

## Critical Implementation Notes

1. **JSON Safety**: Always use proper JSON encoding, never string concatenation
2. **Type Precision**: Maintain numeric precision across languages
3. **Error Messages**: Provide clear, actionable error messages
4. **Extensibility**: Design for easy addition of new types
5. **Performance**: Cache type modules if needed for hot paths

## Next Steps
After implementing serialization:
1. Test each type thoroughly
2. Verify cross-language compatibility
3. Benchmark serialization performance
4. Proceed to integration tests (next prompt)