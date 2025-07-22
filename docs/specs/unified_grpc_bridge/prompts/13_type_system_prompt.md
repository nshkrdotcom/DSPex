# Prompt: Implement the Variable Type System

## Objective
Create a comprehensive type system for variables that ensures type safety across the Elixir-Python boundary. This includes validators, serializers, and constraint checkers for each supported type.

## Context
The type system is crucial for maintaining data integrity. Each type needs validation, constraint checking, and serialization capabilities that work consistently in both languages.

## Requirements

### Core Types to Implement
1. **float** - Floating point numbers with min/max constraints
2. **integer** - Whole numbers with min/max constraints  
3. **string** - Text with length and pattern constraints
4. **boolean** - True/false values

### Each Type Must Support
- Value validation and normalization
- Constraint checking
- Serialization for storage
- Clear error messages

## Implementation Steps

### 1. Define the Type Behaviour

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types.ex

defmodule Snakepit.Bridge.Variables.Types do
  @moduledoc """
  Type system for bridge variables.
  
  Provides a behaviour for implementing variable types and
  a registry for looking up type implementations.
  """
  
  @doc """
  Behaviour that all variable types must implement.
  """
  @callback validate(value :: any()) :: {:ok, any()} | {:error, String.t()}
  @callback validate_constraints(value :: any(), constraints :: map()) :: 
    :ok | {:error, String.t()}
  @callback serialize(value :: any()) :: {:ok, binary()} | {:error, String.t()}
  @callback deserialize(binary :: binary()) :: {:ok, any()} | {:error, String.t()}
  
  # Registry of type implementations
  @type_modules %{
    float: Snakepit.Bridge.Variables.Types.Float,
    integer: Snakepit.Bridge.Variables.Types.Integer,
    string: Snakepit.Bridge.Variables.Types.String,
    boolean: Snakepit.Bridge.Variables.Types.Boolean
  }
  
  @doc """
  Gets the implementation module for a type.
  """
  @spec get_type_module(atom() | String.t()) :: 
    {:ok, module()} | {:error, {:unknown_type, any()}}
  def get_type_module(type) when is_atom(type) do
    case Map.fetch(@type_modules, type) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_type, type}}
    end
  end
  
  def get_type_module(type) when is_binary(type) do
    try do
      get_type_module(String.to_existing_atom(type))
    rescue
      ArgumentError -> {:error, {:unknown_type, type}}
    end
  end
  
  @doc """
  Lists all supported types.
  """
  @spec list_types() :: [atom()]
  def list_types do
    Map.keys(@type_modules)
  end
  
  @doc """
  Validates a value against a type.
  """
  @spec validate_value(any(), atom(), map()) :: {:ok, any()} | {:error, String.t()}
  def validate_value(value, type, constraints \\ %{}) do
    with {:ok, module} <- get_type_module(type),
         {:ok, validated} <- module.validate(value),
         :ok <- module.validate_constraints(validated, constraints) do
      {:ok, validated}
    end
  end
  
  @doc """
  Checks if a value would be valid for a type without modifying it.
  """
  @spec valid?(any(), atom(), map()) :: boolean()
  def valid?(value, type, constraints \\ %{}) do
    case validate_value(value, type, constraints) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end
```

### 2. Implement Float Type

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types/float.ex

defmodule Snakepit.Bridge.Variables.Types.Float do
  @moduledoc """
  Float type implementation for variables.
  
  Supports:
  - Automatic integer to float conversion
  - Min/max constraints
  - Special values (infinity, NaN) for Python compatibility
  """
  
  @behaviour Snakepit.Bridge.Variables.Types
  
  @impl true
  def validate(value) when is_float(value), do: {:ok, value}
  def validate(value) when is_integer(value), do: {:ok, value * 1.0}
  def validate(:infinity), do: {:ok, :infinity}
  def validate(:negative_infinity), do: {:ok, :negative_infinity}
  def validate(:nan), do: {:ok, :nan}
  def validate("Infinity"), do: {:ok, :infinity}
  def validate("-Infinity"), do: {:ok, :negative_infinity}
  def validate("NaN"), do: {:ok, :nan}
  def validate(_), do: {:error, "must be a number"}
  
  @impl true
  def validate_constraints(value, constraints) do
    cond do
      # Special values bypass normal constraints
      value in [:infinity, :negative_infinity, :nan] ->
        :ok
        
      # Check min constraint
      min = Map.get(constraints, :min) ->
        if value >= min do
          validate_constraints(value, Map.delete(constraints, :min))
        else
          {:error, "value #{value} is below minimum #{min}"}
        end
        
      # Check max constraint  
      max = Map.get(constraints, :max) ->
        if value <= max do
          validate_constraints(value, Map.delete(constraints, :max))
        else
          {:error, "value #{value} is above maximum #{max}"}
        end
        
      # No more constraints
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(:infinity), do: {:ok, "Infinity"}
  def serialize(:negative_infinity), do: {:ok, "-Infinity"}
  def serialize(:nan), do: {:ok, "NaN"}
  def serialize(value) when is_float(value) do
    # Use Erlang's float_to_binary for precision
    {:ok, :erlang.float_to_binary(value, [:compact])}
  end
  def serialize(_), do: {:error, "cannot serialize non-float"}
  
  @impl true
  def deserialize("Infinity"), do: {:ok, :infinity}
  def deserialize("-Infinity"), do: {:ok, :negative_infinity}
  def deserialize("NaN"), do: {:ok, :nan}
  def deserialize(binary) when is_binary(binary) do
    case Float.parse(binary) do
      {float, ""} -> {:ok, float}
      {float, _rest} -> {:error, "invalid float format: #{binary}"}
      :error -> {:error, "invalid float: #{binary}"}
    end
  end
  def deserialize(_), do: {:error, "invalid float format"}
end
```

### 3. Implement Integer Type

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types/integer.ex

defmodule Snakepit.Bridge.Variables.Types.Integer do
  @moduledoc """
  Integer type implementation for variables.
  
  Supports:
  - Strict integer validation (no float coercion)
  - Min/max constraints  
  - Large integer support
  """
  
  @behaviour Snakepit.Bridge.Variables.Types
  
  @impl true
  def validate(value) when is_integer(value), do: {:ok, value}
  def validate(value) when is_float(value) do
    # Only allow floats that are whole numbers
    if Float.floor(value) == value and not (is_nan(value) or is_inf(value)) do
      {:ok, trunc(value)}
    else
      {:error, "must be a whole number, got #{value}"}
    end
  end
  def validate(_), do: {:error, "must be an integer"}
  
  @impl true
  def validate_constraints(value, constraints) do
    cond do
      min = Map.get(constraints, :min) ->
        if value >= min do
          validate_constraints(value, Map.delete(constraints, :min))
        else
          {:error, "value #{value} is below minimum #{min}"}
        end
        
      max = Map.get(constraints, :max) ->
        if value <= max do
          validate_constraints(value, Map.delete(constraints, :max))
        else
          {:error, "value #{value} is above maximum #{max}"}
        end
        
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(value) when is_integer(value) do
    {:ok, Integer.to_string(value)}
  end
  def serialize(_), do: {:error, "cannot serialize non-integer"}
  
  @impl true
  def deserialize(binary) when is_binary(binary) do
    case Integer.parse(binary) do
      {integer, ""} -> {:ok, integer}
      {_integer, _rest} -> {:error, "invalid integer format: #{binary}"}
      :error -> {:error, "invalid integer: #{binary}"}
    end
  end
  def deserialize(_), do: {:error, "invalid integer format"}
  
  defp is_nan(value), do: value != value
  defp is_inf(value), do: value in [:infinity, :negative_infinity] or abs(value) == :infinity
end
```

### 4. Implement String Type

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types/string.ex

defmodule Snakepit.Bridge.Variables.Types.String do
  @moduledoc """
  String type implementation for variables.
  
  Supports:
  - Automatic atom to string conversion
  - Length constraints (min_length, max_length)
  - Pattern matching with regex
  - Enumeration constraint (allowed values)
  """
  
  @behaviour Snakepit.Bridge.Variables.Types
  
  @impl true
  def validate(value) when is_binary(value), do: {:ok, value}
  def validate(value) when is_atom(value) and not is_nil(value) do
    {:ok, to_string(value)}
  end
  def validate(nil), do: {:error, "cannot be nil"}
  def validate(_), do: {:error, "must be a string"}
  
  @impl true
  def validate_constraints(value, constraints) do
    length = String.length(value)
    
    cond do
      min_length = Map.get(constraints, :min_length) ->
        if length >= min_length do
          validate_constraints(value, Map.delete(constraints, :min_length))
        else
          {:error, "must be at least #{min_length} characters, got #{length}"}
        end
        
      max_length = Map.get(constraints, :max_length) ->
        if length <= max_length do
          validate_constraints(value, Map.delete(constraints, :max_length))
        else
          {:error, "must be at most #{max_length} characters, got #{length}"}
        end
        
      pattern = Map.get(constraints, :pattern) ->
        regex = compile_pattern(pattern)
        if Regex.match?(regex, value) do
          validate_constraints(value, Map.delete(constraints, :pattern))
        else
          {:error, "must match pattern: #{pattern}"}
        end
        
      enum = Map.get(constraints, :enum) ->
        if value in enum do
          validate_constraints(value, Map.delete(constraints, :enum))
        else
          {:error, "must be one of: #{Enum.join(enum, ", ")}"}
        end
        
      true ->
        :ok
    end
  end
  
  @impl true
  def serialize(value) when is_binary(value) do
    # Strings are already in the right format
    {:ok, value}
  end
  def serialize(_), do: {:error, "cannot serialize non-string"}
  
  @impl true
  def deserialize(value) when is_binary(value) do
    {:ok, value}
  end
  def deserialize(_), do: {:error, "invalid string format"}
  
  defp compile_pattern(pattern) when is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> regex
      {:error, _} -> 
        # If pattern compilation fails, create a literal match regex
        Regex.compile!(Regex.escape(pattern))
    end
  end
  defp compile_pattern(%Regex{} = regex), do: regex
end
```

### 5. Implement Boolean Type

```elixir
# File: snakepit/lib/snakepit/bridge/variables/types/boolean.ex

defmodule Snakepit.Bridge.Variables.Types.Boolean do
  @moduledoc """
  Boolean type implementation for variables.
  
  The simplest type - just true or false with no constraints.
  """
  
  @behaviour Snakepit.Bridge.Variables.Types
  
  @impl true
  def validate(true), do: {:ok, true}
  def validate(false), do: {:ok, false}
  def validate("true"), do: {:ok, true}
  def validate("false"), do: {:ok, false}
  def validate(1), do: {:ok, true}
  def validate(0), do: {:ok, false}
  def validate(_), do: {:error, "must be a boolean (true or false)"}
  
  @impl true
  def validate_constraints(_value, _constraints) do
    # Booleans have no constraints
    :ok
  end
  
  @impl true
  def serialize(true), do: {:ok, "true"}
  def serialize(false), do: {:ok, "false"}
  def serialize(_), do: {:error, "cannot serialize non-boolean"}
  
  @impl true
  def deserialize("true"), do: {:ok, true}
  def deserialize("false"), do: {:ok, false}
  def deserialize(binary) when is_binary(binary) do
    case String.downcase(binary) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      "1" -> {:ok, true}
      "0" -> {:ok, false}
      _ -> {:error, "invalid boolean: #{binary}"}
    end
  end
  def deserialize(_), do: {:error, "invalid boolean format"}
end
```

### 6. Create Type Tests

```elixir
# File: test/snakepit/bridge/variables/types_test.exs

defmodule Snakepit.Bridge.Variables.TypesTest do
  use ExUnit.Case, async: true
  
  alias Snakepit.Bridge.Variables.Types
  
  describe "type registry" do
    test "get_type_module/1" do
      assert {:ok, Types.Float} = Types.get_type_module(:float)
      assert {:ok, Types.Integer} = Types.get_type_module(:integer)
      assert {:ok, Types.String} = Types.get_type_module(:string)
      assert {:ok, Types.Boolean} = Types.get_type_module(:boolean)
      
      # String type names
      assert {:ok, Types.Float} = Types.get_type_module("float")
      
      # Unknown type
      assert {:error, {:unknown_type, :unknown}} = Types.get_type_module(:unknown)
    end
    
    test "list_types/0" do
      types = Types.list_types()
      assert :float in types
      assert :integer in types
      assert :string in types
      assert :boolean in types
    end
  end
  
  describe "float type" do
    test "validation" do
      assert {:ok, 3.14} = Types.validate_value(3.14, :float)
      assert {:ok, 42.0} = Types.validate_value(42, :float)
      assert {:ok, :infinity} = Types.validate_value(:infinity, :float)
      assert {:ok, :nan} = Types.validate_value(:nan, :float)
      
      assert {:error, _} = Types.validate_value("not a number", :float)
    end
    
    test "constraints" do
      constraints = %{min: 0.0, max: 1.0}
      assert {:ok, 0.5} = Types.validate_value(0.5, :float, constraints)
      assert {:error, msg} = Types.validate_value(-0.5, :float, constraints)
      assert msg =~ "below minimum"
      assert {:error, msg} = Types.validate_value(1.5, :float, constraints)
      assert msg =~ "above maximum"
    end
    
    test "serialization" do
      alias Types.Float
      
      assert {:ok, "3.14"} = Float.serialize(3.14)
      assert {:ok, "Infinity"} = Float.serialize(:infinity)
      assert {:ok, "-Infinity"} = Float.serialize(:negative_infinity)
      assert {:ok, "NaN"} = Float.serialize(:nan)
      
      assert {:ok, 3.14} = Float.deserialize("3.14")
      assert {:ok, :infinity} = Float.deserialize("Infinity")
    end
  end
  
  describe "integer type" do
    test "validation" do
      assert {:ok, 42} = Types.validate_value(42, :integer)
      assert {:ok, -100} = Types.validate_value(-100, :integer)
      assert {:ok, 0} = Types.validate_value(0, :integer)
      
      # Whole number floats accepted
      assert {:ok, 42} = Types.validate_value(42.0, :integer)
      
      # Non-whole floats rejected
      assert {:error, _} = Types.validate_value(3.14, :integer)
      assert {:error, _} = Types.validate_value("42", :integer)
    end
    
    test "constraints" do
      constraints = %{min: 0, max: 100}
      assert {:ok, 50} = Types.validate_value(50, :integer, constraints)
      assert {:error, _} = Types.validate_value(-1, :integer, constraints)
      assert {:error, _} = Types.validate_value(101, :integer, constraints)
    end
    
    test "serialization" do
      alias Types.Integer
      
      assert {:ok, "42"} = Integer.serialize(42)
      assert {:ok, "-100"} = Integer.serialize(-100)
      assert {:ok, "0"} = Integer.serialize(0)
      
      assert {:ok, 42} = Integer.deserialize("42")
      assert {:ok, -100} = Integer.deserialize("-100")
    end
  end
  
  describe "string type" do
    test "validation" do
      assert {:ok, "hello"} = Types.validate_value("hello", :string)
      assert {:ok, ""} = Types.validate_value("", :string)
      assert {:ok, "test"} = Types.validate_value(:test, :string)
      
      assert {:error, _} = Types.validate_value(nil, :string)
      assert {:error, _} = Types.validate_value(123, :string)
    end
    
    test "length constraints" do
      constraints = %{min_length: 3, max_length: 10}
      assert {:ok, "hello"} = Types.validate_value("hello", :string, constraints)
      assert {:error, msg} = Types.validate_value("hi", :string, constraints)
      assert msg =~ "at least 3 characters"
      assert {:error, msg} = Types.validate_value("this is too long", :string, constraints)
      assert msg =~ "at most 10 characters"
    end
    
    test "pattern constraint" do
      constraints = %{pattern: "^[A-Z][a-z]+$"}
      assert {:ok, "Hello"} = Types.validate_value("Hello", :string, constraints)
      assert {:error, _} = Types.validate_value("hello", :string, constraints)
      assert {:error, _} = Types.validate_value("HELLO", :string, constraints)
    end
    
    test "enum constraint" do
      constraints = %{enum: ["red", "green", "blue"]}
      assert {:ok, "red"} = Types.validate_value("red", :string, constraints)
      assert {:error, msg} = Types.validate_value("yellow", :string, constraints)
      assert msg =~ "must be one of: red, green, blue"
    end
  end
  
  describe "boolean type" do
    test "validation" do
      assert {:ok, true} = Types.validate_value(true, :boolean)
      assert {:ok, false} = Types.validate_value(false, :boolean)
      assert {:ok, true} = Types.validate_value("true", :boolean)
      assert {:ok, false} = Types.validate_value("false", :boolean)
      assert {:ok, true} = Types.validate_value(1, :boolean)
      assert {:ok, false} = Types.validate_value(0, :boolean)
      
      assert {:error, _} = Types.validate_value("yes", :boolean)
      assert {:error, _} = Types.validate_value(nil, :boolean)
    end
    
    test "serialization" do
      alias Types.Boolean
      
      assert {:ok, "true"} = Boolean.serialize(true)
      assert {:ok, "false"} = Boolean.serialize(false)
      
      assert {:ok, true} = Boolean.deserialize("true")
      assert {:ok, false} = Boolean.deserialize("false")
      assert {:ok, true} = Boolean.deserialize("TRUE")
      assert {:ok, false} = Boolean.deserialize("FALSE")
    end
  end
  
  describe "cross-type validation" do
    test "valid?/3 helper" do
      assert Types.valid?(3.14, :float)
      assert Types.valid?(42, :integer)
      assert Types.valid?("hello", :string)
      assert Types.valid?(true, :boolean)
      
      refute Types.valid?("not a number", :float)
      refute Types.valid?(3.14, :integer)
      refute Types.valid?(nil, :string)
      refute Types.valid?("yes", :boolean)
    end
  end
end
```

## Type System Design Principles

1. **Validation vs Coercion**:
   - Be strict about types but allow reasonable conversions
   - Integer accepts whole number floats
   - String accepts atoms
   - Boolean accepts common representations

2. **Constraint Philosophy**:
   - Constraints are optional
   - Multiple constraints can be combined
   - Clear error messages indicate which constraint failed

3. **Serialization Format**:
   - Use simple string representation
   - Handle special values (infinity, NaN)
   - Maintain precision for numbers

4. **Error Messages**:
   - Be specific about what went wrong
   - Include the invalid value when safe
   - Suggest valid alternatives

## Cross-Language Compatibility Notes

1. **Float Special Values**:
   - Elixir doesn't have native NaN/Infinity
   - Use atoms to represent these
   - Serialize to standard strings

2. **Integer Precision**:
   - Both languages support arbitrary precision
   - Use string serialization to preserve

3. **String Encoding**:
   - UTF-8 everywhere
   - No special handling needed

4. **Boolean Flexibility**:
   - Accept multiple representations
   - Normalize to true/false

## Files to Create

1. Create: `snakepit/lib/snakepit/bridge/variables/types.ex`
2. Create: `snakepit/lib/snakepit/bridge/variables/types/float.ex`
3. Create: `snakepit/lib/snakepit/bridge/variables/types/integer.ex`
4. Create: `snakepit/lib/snakepit/bridge/variables/types/string.ex`
5. Create: `snakepit/lib/snakepit/bridge/variables/types/boolean.ex`
6. Create: `test/snakepit/bridge/variables/types_test.exs`

## Next Steps

After implementing the type system:
1. Run all type tests to verify behavior
2. Test edge cases (large numbers, empty strings, etc.)
3. Verify serialization round-trips correctly
4. Proceed to implement gRPC handlers (next prompt)