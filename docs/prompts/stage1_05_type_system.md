# Stage 1 Prompt 5: Type System and Validation

## OBJECTIVE

Implement a comprehensive type system and validation framework that bridges Elixir types with ML-specific requirements, providing runtime validation, type coercion, constraint checking, and integration with both ExDantic patterns and DSPy type requirements. This system must handle basic types, composite types, ML-specific types, and provider-specific serialization.

## COMPLETE IMPLEMENTATION CONTEXT

### TYPE SYSTEM ARCHITECTURE OVERVIEW

From the signature innovation documents and ExDantic integration analysis:

```
┌─────────────────────────────────────────────────────────────┐
│                    Type System Architecture                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Type Registry   │  │ Validation      │  │ Serialization││
│  │ - Basic types   │  │ Engine          │  │ Engine       ││
│  │ - ML types      │  │ - Runtime check │  │ - JSON Schema││
│  │ - Composite     │  │ - Constraints   │  │ - Provider   ││
│  │ - Custom        │  │ - Coercion      │  │   formats    ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ ExDantic        │  │ DSPy Types      │  │ Ash Types    ││
│  │ Integration     │  │ Integration     │  │ Integration  ││
│  │ - Schemas       │  │ - Field mapping │  │ - Attributes ││
│  │ - Validation    │  │ - Type conversion│  │ - Constraints││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### COMPLETE TYPE DEFINITIONS

From STAGE_1_FOUNDATION_IMPLEMENTATION.md and type system analysis:

**Basic Types:**
```elixir
@basic_types [
  :string,      # Text data, questions, responses
  :integer,     # Numeric values, counts, indices  
  :float,       # Decimal numbers, scores
  :boolean,     # Binary flags, yes/no responses
  :atom,        # Enumerated values, status indicators
  :any,         # Unconstrained values, debugging
  :map,         # Structured data, complex inputs
  :binary       # Raw binary data, images, files
]
```

**ML-Specific Types:**
```elixir
@ml_types [
  :embedding,        # Vector embeddings for semantic search
  :probability,      # Values constrained 0.0-1.0
  :confidence_score, # Model confidence metrics
  :reasoning_chain,  # Step-by-step reasoning traces
  :token_count,      # Token usage tracking
  :model_output,     # Raw model responses
  :prompt_template,  # Template strings with variables
  :function_call,    # Structured function calling data
  :tool_result      # Results from tool/function execution
]
```

**Composite Types:**
```elixir
@composite_types [
  {:list, inner_type},              # Arrays of values
  {:dict, key_type, value_type},    # Key-value mappings
  {:union, [type1, type2, ...]},    # One of multiple types
  {:optional, inner_type},          # Nullable values
  {:constrained, base_type, constraints}, # Type with constraints
  {:tagged, tag, inner_type}        # Tagged union types
]
```

### EXDANTIC INTEGRATION PATTERNS

From ../../exdantic/README.md analysis:

**ExDantic Core Features for Integration:**
- Runtime schema creation and validation
- TypeAdapter pattern for custom types
- Field validation with constraints
- JSON schema generation
- Nested validation for complex structures

**ExDantic Pattern Integration:**
```elixir
defmodule DSPex.Types.ExDanticAdapter do
  @moduledoc """
  Integration adapter for ExDantic validation patterns.
  """
  
  def create_schema(field_definitions) do
    fields = Enum.map(field_definitions, fn {name, type, constraints} ->
      {name, convert_to_exdantic_type(type, constraints)}
    end)
    
    ExDantic.schema(fields)
  end
  
  defp convert_to_exdantic_type(:string, constraints) do
    base_type = ExDantic.Types.String.new()
    apply_string_constraints(base_type, constraints)
  end
  
  defp convert_to_exdantic_type(:integer, constraints) do
    base_type = ExDantic.Types.Integer.new()
    apply_numeric_constraints(base_type, constraints)
  end
  
  defp convert_to_exdantic_type({:list, inner_type}, constraints) do
    inner = convert_to_exdantic_type(inner_type, [])
    base_type = ExDantic.Types.List.new(inner)
    apply_list_constraints(base_type, constraints)
  end
  
  # ... additional type conversions
end
```

### COMPREHENSIVE TYPE REGISTRY

**Core Type Registry Implementation:**
```elixir
defmodule DSPex.Types.Registry do
  @moduledoc """
  Central registry for all type definitions and metadata.
  """
  
  @basic_types %{
    :string => %{
      validator: &validate_string/2,
      serializer: &serialize_string/2,
      constraints: [:min_length, :max_length, :pattern, :format],
      json_schema: %{type: "string"},
      python_type: "str",
      ash_type: :string
    },
    :integer => %{
      validator: &validate_integer/2,
      serializer: &serialize_integer/2,
      constraints: [:min, :max, :multiple_of],
      json_schema: %{type: "integer"},
      python_type: "int", 
      ash_type: :integer
    },
    :float => %{
      validator: &validate_float/2,
      serializer: &serialize_float/2,
      constraints: [:min, :max, :precision],
      json_schema: %{type: "number"},
      python_type: "float",
      ash_type: :float
    },
    :boolean => %{
      validator: &validate_boolean/2,
      serializer: &serialize_boolean/2,
      constraints: [],
      json_schema: %{type: "boolean"},
      python_type: "bool",
      ash_type: :boolean
    },
    :atom => %{
      validator: &validate_atom/2,
      serializer: &serialize_atom/2,
      constraints: [:one_of],
      json_schema: %{type: "string"},
      python_type: "str",
      ash_type: :atom
    }
  }
  
  @ml_types %{
    :embedding => %{
      validator: &validate_embedding/2,
      serializer: &serialize_embedding/2,
      constraints: [:dimensions, :min_value, :max_value],
      json_schema: %{type: "array", items: %{type: "number"}},
      python_type: "List[float]",
      ash_type: {:array, :float}
    },
    :probability => %{
      validator: &validate_probability/2,
      serializer: &serialize_probability/2,
      constraints: [],
      json_schema: %{type: "number", minimum: 0.0, maximum: 1.0},
      python_type: "float",
      ash_type: :float
    },
    :confidence_score => %{
      validator: &validate_confidence_score/2,
      serializer: &serialize_confidence_score/2,
      constraints: [],
      json_schema: %{type: "number", minimum: 0.0, maximum: 1.0},
      python_type: "float",
      ash_type: :float
    },
    :reasoning_chain => %{
      validator: &validate_reasoning_chain/2,
      serializer: &serialize_reasoning_chain/2,
      constraints: [:max_steps, :step_format],
      json_schema: %{type: "array", items: %{type: "string"}},
      python_type: "List[str]",
      ash_type: {:array, :string}
    },
    :token_count => %{
      validator: &validate_token_count/2,
      serializer: &serialize_token_count/2,
      constraints: [:max_tokens],
      json_schema: %{type: "integer", minimum: 0},
      python_type: "int",
      ash_type: :integer
    }
  }
  
  def get_type_info(type) do
    case type do
      basic when is_atom(basic) ->
        Map.get(@basic_types, basic) || Map.get(@ml_types, basic)
      
      {:list, inner_type} ->
        case get_type_info(inner_type) do
          nil -> nil
          inner_info ->
            %{
              validator: &validate_list/2,
              serializer: &serialize_list/2,
              constraints: [:min_length, :max_length, :unique],
              json_schema: %{type: "array", items: inner_info.json_schema},
              python_type: "List[#{inner_info.python_type}]",
              ash_type: {:array, inner_info.ash_type},
              inner_type: inner_type
            }
        end
      
      {:dict, key_type, value_type} ->
        with key_info when not is_nil(key_info) <- get_type_info(key_type),
             value_info when not is_nil(value_info) <- get_type_info(value_type) do
          %{
            validator: &validate_dict/2,
            serializer: &serialize_dict/2,
            constraints: [:min_size, :max_size, :required_keys],
            json_schema: %{
              type: "object",
              additionalProperties: value_info.json_schema
            },
            python_type: "Dict[#{key_info.python_type}, #{value_info.python_type}]",
            ash_type: :map,
            key_type: key_type,
            value_type: value_type
          }
        else
          _ -> nil
        end
      
      {:union, types} ->
        type_infos = Enum.map(types, &get_type_info/1)
        if Enum.all?(type_infos, & &1) do
          %{
            validator: &validate_union/2,
            serializer: &serialize_union/2,
            constraints: [],
            json_schema: %{anyOf: Enum.map(type_infos, & &1.json_schema)},
            python_type: "Union[#{Enum.map(type_infos, & &1.python_type) |> Enum.join(", ")}]",
            ash_type: :union,
            union_types: types
          }
        else
          nil
        end
      
      _ -> nil
    end
  end
  
  def list_types do
    Map.keys(@basic_types) ++ Map.keys(@ml_types)
  end
  
  def is_basic_type?(type), do: Map.has_key?(@basic_types, type)
  def is_ml_type?(type), do: Map.has_key?(@ml_types, type)
  def is_composite_type?(type), do: is_tuple(type)
end
```

### VALIDATION ENGINE IMPLEMENTATION

**Core Validation Engine:**
```elixir
defmodule DSPex.Types.Validator do
  @moduledoc """
  Core validation engine for type checking and constraint validation.
  """
  
  alias DSPex.Types.Registry
  
  def validate_value(value, type, constraints \\ []) do
    case Registry.get_type_info(type) do
      nil ->
        {:error, "Unknown type: #{inspect(type)}"}
      
      type_info ->
        case apply_validator(value, type, type_info, constraints) do
          {:ok, validated_value} ->
            apply_constraints(validated_value, type, constraints)
          
          error ->
            error
        end
    end
  end
  
  defp apply_validator(value, type, type_info, constraints) do
    type_info.validator.(value, {type, type_info, constraints})
  end
  
  defp apply_constraints(value, type, constraints) do
    case Registry.get_type_info(type) do
      %{constraints: allowed_constraints} ->
        validate_constraints(value, type, constraints, allowed_constraints)
      _ ->
        {:ok, value}
    end
  end
  
  defp validate_constraints(value, _type, [], _allowed) do
    {:ok, value}
  end
  
  defp validate_constraints(value, type, [{constraint, constraint_value} | rest], allowed) do
    if constraint in allowed do
      case apply_constraint(value, type, constraint, constraint_value) do
        :ok ->
          validate_constraints(value, type, rest, allowed)
        
        {:error, reason} ->
          {:error, "Constraint #{constraint} failed: #{reason}"}
      end
    else
      {:error, "Unsupported constraint #{constraint} for type #{type}"}
    end
  end
  
  # Basic type validators
  defp validate_string(value, _context) when is_binary(value), do: {:ok, value}
  defp validate_string(value, _context), do: {:error, "Expected string, got #{inspect(value)}"}
  
  defp validate_integer(value, _context) when is_integer(value), do: {:ok, value}
  defp validate_integer(value, _context) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Cannot convert to integer: #{inspect(value)}"}
    end
  end
  defp validate_integer(value, _context), do: {:error, "Expected integer, got #{inspect(value)}"}
  
  defp validate_float(value, _context) when is_float(value), do: {:ok, value}
  defp validate_float(value, _context) when is_integer(value), do: {:ok, value / 1}
  defp validate_float(value, _context) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "Cannot convert to float: #{inspect(value)}"}
    end
  end
  defp validate_float(value, _context), do: {:error, "Expected float, got #{inspect(value)}"}
  
  defp validate_boolean(true, _context), do: {:ok, true}
  defp validate_boolean(false, _context), do: {:ok, false}
  defp validate_boolean("true", _context), do: {:ok, true}
  defp validate_boolean("false", _context), do: {:ok, false}
  defp validate_boolean(1, _context), do: {:ok, true}
  defp validate_boolean(0, _context), do: {:ok, false}
  defp validate_boolean(value, _context), do: {:error, "Expected boolean, got #{inspect(value)}"}
  
  defp validate_atom(value, _context) when is_atom(value), do: {:ok, value}
  defp validate_atom(value, _context) when is_binary(value) do
    try do
      {:ok, String.to_existing_atom(value)}
    rescue
      ArgumentError -> {:ok, String.to_atom(value)}
    end
  end
  defp validate_atom(value, _context), do: {:error, "Expected atom, got #{inspect(value)}"}
  
  # ML type validators
  defp validate_embedding(value, _context) when is_list(value) do
    if Enum.all?(value, &is_number/1) do
      {:ok, Enum.map(value, &(if is_integer(&1), do: &1 / 1, else: &1))}
    else
      {:error, "Embedding must be a list of numbers"}
    end
  end
  defp validate_embedding(value, _context), do: {:error, "Expected list for embedding, got #{inspect(value)}"}
  
  defp validate_probability(value, _context) when is_number(value) and value >= 0.0 and value <= 1.0 do
    {:ok, if(is_integer(value), do: value / 1, else: value)}
  end
  defp validate_probability(value, _context) when is_number(value) do
    {:error, "Probability must be between 0.0 and 1.0, got #{value}"}
  end
  defp validate_probability(value, _context), do: {:error, "Expected number for probability, got #{inspect(value)}"}
  
  defp validate_confidence_score(value, context), do: validate_probability(value, context)
  
  defp validate_reasoning_chain(value, _context) when is_list(value) do
    if Enum.all?(value, &is_binary/1) do
      {:ok, value}
    else
      {:error, "Reasoning chain must be a list of strings"}
    end
  end
  defp validate_reasoning_chain(value, _context), do: {:error, "Expected list for reasoning chain, got #{inspect(value)}"}
  
  defp validate_token_count(value, _context) when is_integer(value) and value >= 0, do: {:ok, value}
  defp validate_token_count(value, _context) when is_integer(value) do
    {:error, "Token count must be non-negative, got #{value}"}
  end
  defp validate_token_count(value, _context), do: {:error, "Expected integer for token count, got #{inspect(value)}"}
  
  # Composite type validators
  defp validate_list(value, {_type, %{inner_type: inner_type}, constraints}) when is_list(value) do
    case validate_list_items(value, inner_type, []) do
      {:ok, validated_items} ->
        apply_list_constraints(validated_items, constraints)
      error ->
        error
    end
  end
  defp validate_list(value, _context), do: {:error, "Expected list, got #{inspect(value)}"}
  
  defp validate_list_items([], _inner_type, acc), do: {:ok, Enum.reverse(acc)}
  defp validate_list_items([item | rest], inner_type, acc) do
    case validate_value(item, inner_type) do
      {:ok, validated} ->
        validate_list_items(rest, inner_type, [validated | acc])
      error ->
        error
    end
  end
  
  defp validate_dict(value, {_type, %{key_type: key_type, value_type: value_type}, constraints}) when is_map(value) do
    case validate_dict_entries(Map.to_list(value), key_type, value_type, []) do
      {:ok, validated_entries} ->
        validated_map = Map.new(validated_entries)
        apply_dict_constraints(validated_map, constraints)
      error ->
        error
    end
  end
  defp validate_dict(value, _context), do: {:error, "Expected map, got #{inspect(value)}"}
  
  defp validate_dict_entries([], _key_type, _value_type, acc), do: {:ok, Enum.reverse(acc)}
  defp validate_dict_entries([{key, value} | rest], key_type, value_type, acc) do
    with {:ok, validated_key} <- validate_value(key, key_type),
         {:ok, validated_value} <- validate_value(value, value_type) do
      validate_dict_entries(rest, key_type, value_type, [{validated_key, validated_value} | acc])
    else
      error -> error
    end
  end
  
  defp validate_union(value, {_type, %{union_types: types}, _constraints}) do
    try_union_types(value, types)
  end
  
  defp try_union_types(value, []), do: {:error, "Value does not match any union type: #{inspect(value)}"}
  defp try_union_types(value, [type | rest]) do
    case validate_value(value, type) do
      {:ok, validated} -> {:ok, validated}
      {:error, _} -> try_union_types(value, rest)
    end
  end
  
  # Constraint applications
  defp apply_constraint(value, :string, :min_length, min) when byte_size(value) >= min, do: :ok
  defp apply_constraint(value, :string, :min_length, min), do: {:error, "String too short (minimum #{min})"}
  
  defp apply_constraint(value, :string, :max_length, max) when byte_size(value) <= max, do: :ok
  defp apply_constraint(value, :string, :max_length, max), do: {:error, "String too long (maximum #{max})"}
  
  defp apply_constraint(value, :string, :pattern, pattern) do
    if Regex.match?(pattern, value) do
      :ok
    else
      {:error, "String does not match pattern"}
    end
  end
  
  defp apply_constraint(value, type, :min, min) when type in [:integer, :float] and value >= min, do: :ok
  defp apply_constraint(value, type, :min, min) when type in [:integer, :float], do: {:error, "Value too small (minimum #{min})"}
  
  defp apply_constraint(value, type, :max, max) when type in [:integer, :float] and value <= max, do: :ok
  defp apply_constraint(value, type, :max, max) when type in [:integer, :float], do: {:error, "Value too large (maximum #{max})"}
  
  defp apply_constraint(value, :atom, :one_of, allowed) when value in allowed, do: :ok
  defp apply_constraint(value, :atom, :one_of, allowed), do: {:error, "Value not in allowed list: #{inspect(allowed)}"}
  
  defp apply_constraint(value, :embedding, :dimensions, dim) when length(value) == dim, do: :ok
  defp apply_constraint(value, :embedding, :dimensions, dim), do: {:error, "Embedding must have #{dim} dimensions"}
  
  defp apply_list_constraints(list, constraints) do
    Enum.reduce_while(constraints, {:ok, list}, fn {constraint, value}, {:ok, acc} ->
      case apply_list_constraint(acc, constraint, value) do
        :ok -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
  end
  
  defp apply_list_constraint(list, :min_length, min) when length(list) >= min, do: :ok
  defp apply_list_constraint(list, :min_length, min), do: {:error, "List too short (minimum #{min})"}
  
  defp apply_list_constraint(list, :max_length, max) when length(list) <= max, do: :ok
  defp apply_list_constraint(list, :max_length, max), do: {:error, "List too long (maximum #{max})"}
  
  defp apply_list_constraint(list, :unique, true) do
    if length(list) == length(Enum.uniq(list)) do
      :ok
    else
      {:error, "List items must be unique"}
    end
  end
  
  defp apply_dict_constraints(dict, constraints) do
    Enum.reduce_while(constraints, {:ok, dict}, fn {constraint, value}, {:ok, acc} ->
      case apply_dict_constraint(acc, constraint, value) do
        :ok -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
  end
  
  defp apply_dict_constraint(dict, :min_size, min) when map_size(dict) >= min, do: :ok
  defp apply_dict_constraint(dict, :min_size, min), do: {:error, "Dict too small (minimum #{min})"}
  
  defp apply_dict_constraint(dict, :max_size, max) when map_size(dict) <= max, do: :ok
  defp apply_dict_constraint(dict, :max_size, max), do: {:error, "Dict too large (maximum #{max})"}
  
  defp apply_dict_constraint(dict, :required_keys, keys) do
    missing = Enum.filter(keys, &(not Map.has_key?(dict, &1)))
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required keys: #{inspect(missing)}"}
    end
  end
end
```

### SERIALIZATION ENGINE

**Multi-Target Serialization:**
```elixir
defmodule DSPex.Types.Serializer do
  @moduledoc """
  Serialization engine for converting types to various target formats.
  """
  
  alias DSPex.Types.Registry
  
  def serialize(value, type, target_format, opts \\ []) do
    case Registry.get_type_info(type) do
      nil ->
        {:error, "Unknown type: #{inspect(type)}"}
      
      type_info ->
        apply_serializer(value, type, type_info, target_format, opts)
    end
  end
  
  defp apply_serializer(value, type, type_info, target_format, opts) do
    case target_format do
      :json_schema ->
        generate_json_schema(type, type_info, opts)
      
      :python_type ->
        {:ok, type_info.python_type}
      
      :ash_type ->
        {:ok, type_info.ash_type}
      
      :openai_function ->
        generate_openai_schema(value, type, type_info, opts)
      
      :anthropic_function ->
        generate_anthropic_schema(value, type, type_info, opts)
      
      :json ->
        serialize_to_json(value, type, type_info, opts)
      
      _ ->
        {:error, "Unknown target format: #{target_format}"}
    end
  end
  
  defp generate_json_schema(type, type_info, opts) do
    base_schema = type_info.json_schema
    
    # Apply constraints to schema
    constraints = Keyword.get(opts, :constraints, [])
    enhanced_schema = apply_constraints_to_schema(base_schema, type, constraints)
    
    {:ok, enhanced_schema}
  end
  
  defp apply_constraints_to_schema(schema, :string, constraints) do
    Enum.reduce(constraints, schema, fn {constraint, value}, acc ->
      case constraint do
        :min_length -> Map.put(acc, :minLength, value)
        :max_length -> Map.put(acc, :maxLength, value)
        :pattern -> Map.put(acc, :pattern, Regex.source(value))
        :format -> Map.put(acc, :format, value)
        _ -> acc
      end
    end)
  end
  
  defp apply_constraints_to_schema(schema, type, constraints) when type in [:integer, :float] do
    Enum.reduce(constraints, schema, fn {constraint, value}, acc ->
      case constraint do
        :min -> Map.put(acc, :minimum, value)
        :max -> Map.put(acc, :maximum, value)
        :multiple_of -> Map.put(acc, :multipleOf, value)
        _ -> acc
      end
    end)
  end
  
  defp apply_constraints_to_schema(schema, :atom, constraints) do
    case Keyword.get(constraints, :one_of) do
      nil -> schema
      values -> Map.put(schema, :enum, Enum.map(values, &to_string/1))
    end
  end
  
  defp apply_constraints_to_schema(schema, _type, _constraints), do: schema
  
  defp generate_openai_schema(value, type, type_info, opts) do
    {:ok, base_schema} = generate_json_schema(type, type_info, opts)
    
    # OpenAI specific enhancements
    openai_schema = base_schema
                   |> Map.put(:description, Keyword.get(opts, :description, ""))
                   |> maybe_add_examples(value, opts)
    
    {:ok, openai_schema}
  end
  
  defp generate_anthropic_schema(value, type, type_info, opts) do
    # Anthropic uses similar schema to OpenAI but with some differences
    {:ok, openai_schema} = generate_openai_schema(value, type, type_info, opts)
    
    # Anthropic specific modifications
    anthropic_schema = openai_schema
                      |> Map.delete(:examples)  # Anthropic doesn't use examples
                      |> maybe_add_anthropic_hints(type, opts)
    
    {:ok, anthropic_schema}
  end
  
  defp serialize_to_json(value, _type, _type_info, _opts) do
    case Jason.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "JSON encoding failed: #{inspect(reason)}"}
    end
  end
  
  defp maybe_add_examples(schema, value, opts) do
    examples = Keyword.get(opts, :examples, [])
    if Enum.empty?(examples) and not is_nil(value) do
      Map.put(schema, :examples, [value])
    else
      Map.put(schema, :examples, examples)
    end
  end
  
  defp maybe_add_anthropic_hints(schema, :embedding, _opts) do
    Map.put(schema, :description, "Vector embedding represented as array of floats")
  end
  
  defp maybe_add_anthropic_hints(schema, :reasoning_chain, _opts) do
    Map.put(schema, :description, "Step-by-step reasoning represented as array of strings")
  end
  
  defp maybe_add_anthropic_hints(schema, _type, _opts), do: schema
  
  # Individual type serializers (used by Registry)
  def serialize_string(value, _context), do: {:ok, value}
  def serialize_integer(value, _context), do: {:ok, value}
  def serialize_float(value, _context), do: {:ok, value}
  def serialize_boolean(value, _context), do: {:ok, value}
  def serialize_atom(value, _context), do: {:ok, to_string(value)}
  
  def serialize_embedding(value, _context), do: {:ok, value}
  def serialize_probability(value, _context), do: {:ok, value}
  def serialize_confidence_score(value, _context), do: {:ok, value}
  def serialize_reasoning_chain(value, _context), do: {:ok, value}
  
  def serialize_list(value, {_type, %{inner_type: inner_type}, _constraints}) do
    case serialize_list_items(value, inner_type, []) do
      {:ok, serialized_items} -> {:ok, serialized_items}
      error -> error
    end
  end
  
  defp serialize_list_items([], _inner_type, acc), do: {:ok, Enum.reverse(acc)}
  defp serialize_list_items([item | rest], inner_type, acc) do
    case serialize(item, inner_type, :json) do
      {:ok, serialized} ->
        serialize_list_items(rest, inner_type, [serialized | acc])
      error ->
        error
    end
  end
  
  def serialize_dict(value, {_type, %{key_type: key_type, value_type: value_type}, _constraints}) do
    case serialize_dict_entries(Map.to_list(value), key_type, value_type, []) do
      {:ok, serialized_entries} -> {:ok, Map.new(serialized_entries)}
      error -> error
    end
  end
  
  defp serialize_dict_entries([], _key_type, _value_type, acc), do: {:ok, Enum.reverse(acc)}
  defp serialize_dict_entries([{key, value} | rest], key_type, value_type, acc) do
    with {:ok, serialized_key} <- serialize(key, key_type, :json),
         {:ok, serialized_value} <- serialize(value, value_type, :json) do
      serialize_dict_entries(rest, key_type, value_type, [{serialized_key, serialized_value} | acc])
    else
      error -> error
    end
  end
  
  def serialize_union(value, {_type, %{union_types: types}, _constraints}) do
    # Find the first type that validates and serialize with that
    find_matching_union_type(value, types)
  end
  
  defp find_matching_union_type(value, []), do: {:error, "No matching union type for value"}
  defp find_matching_union_type(value, [type | rest]) do
    case DSPex.Types.Validator.validate_value(value, type) do
      {:ok, _} -> serialize(value, type, :json)
      {:error, _} -> find_matching_union_type(value, rest)
    end
  end
end
```

### INTEGRATION WITH ASH TYPES

**Ash Type Integration:**
```elixir
defmodule DSPex.Types.AshIntegration do
  @moduledoc """
  Integration layer for Ash resource attributes and types.
  """
  
  def define_ash_attribute(name, dspy_type, constraints \\ []) do
    case convert_to_ash_type(dspy_type) do
      {:ok, ash_type} ->
        ash_constraints = convert_constraints_to_ash(constraints, dspy_type)
        
        quote do
          attribute unquote(name), unquote(ash_type) do
            unquote_splicing(ash_constraints)
            public? true
          end
        end
      
      {:error, reason} ->
        raise "Cannot convert DSPy type #{inspect(dspy_type)} to Ash type: #{reason}"
    end
  end
  
  defp convert_to_ash_type(dspy_type) do
    case DSPex.Types.Registry.get_type_info(dspy_type) do
      %{ash_type: ash_type} -> {:ok, ash_type}
      nil -> {:error, "Unknown DSPy type: #{inspect(dspy_type)}"}
    end
  end
  
  defp convert_constraints_to_ash(constraints, dspy_type) do
    ash_constraints = case dspy_type do
      :string ->
        Enum.flat_map(constraints, fn
          {:min_length, value} -> [min_length: value]
          {:max_length, value} -> [max_length: value]
          _ -> []
        end)
      
      type when type in [:integer, :float] ->
        Enum.flat_map(constraints, fn
          {:min, value} -> [min: value]
          {:max, value} -> [max: value]
          _ -> []
        end)
      
      :atom ->
        case Keyword.get(constraints, :one_of) do
          nil -> []
          values -> [one_of: values]
        end
      
      _ -> []
    end
    
    if Enum.empty?(ash_constraints) do
      []
    else
      [constraints: ash_constraints]
    end
  end
end
```

### COMPREHENSIVE TESTING FRAMEWORK

**Type System Testing:**
```elixir
defmodule DSPex.Types.ValidatorTest do
  use ExUnit.Case
  
  alias DSPex.Types.Validator
  
  describe "basic type validation" do
    test "validates strings correctly" do
      assert {:ok, "hello"} = Validator.validate_value("hello", :string)
      assert {:error, _} = Validator.validate_value(123, :string)
    end
    
    test "validates integers with coercion" do
      assert {:ok, 42} = Validator.validate_value(42, :integer)
      assert {:ok, 42} = Validator.validate_value("42", :integer)
      assert {:error, _} = Validator.validate_value("abc", :integer)
    end
    
    test "validates floats with coercion" do
      assert {:ok, 3.14} = Validator.validate_value(3.14, :float)
      assert {:ok, 42.0} = Validator.validate_value(42, :float)
      assert {:ok, 3.14} = Validator.validate_value("3.14", :float)
    end
    
    test "validates booleans with coercion" do
      assert {:ok, true} = Validator.validate_value(true, :boolean)
      assert {:ok, true} = Validator.validate_value("true", :boolean)
      assert {:ok, true} = Validator.validate_value(1, :boolean)
      assert {:ok, false} = Validator.validate_value(false, :boolean)
      assert {:ok, false} = Validator.validate_value("false", :boolean)
      assert {:ok, false} = Validator.validate_value(0, :boolean)
    end
  end
  
  describe "ML type validation" do
    test "validates embeddings" do
      embedding = [0.1, 0.2, 0.3, 0.4, 0.5]
      assert {:ok, ^embedding} = Validator.validate_value(embedding, :embedding)
      
      assert {:error, _} = Validator.validate_value([1, "two", 3], :embedding)
      assert {:error, _} = Validator.validate_value("not a list", :embedding)
    end
    
    test "validates probabilities" do
      assert {:ok, 0.5} = Validator.validate_value(0.5, :probability)
      assert {:ok, 0.0} = Validator.validate_value(0.0, :probability)
      assert {:ok, 1.0} = Validator.validate_value(1.0, :probability)
      
      assert {:error, _} = Validator.validate_value(-0.1, :probability)
      assert {:error, _} = Validator.validate_value(1.1, :probability)
      assert {:error, _} = Validator.validate_value("0.5", :probability)
    end
    
    test "validates reasoning chains" do
      chain = ["step 1", "step 2", "step 3"]
      assert {:ok, ^chain} = Validator.validate_value(chain, :reasoning_chain)
      
      assert {:error, _} = Validator.validate_value([1, 2, 3], :reasoning_chain)
      assert {:error, _} = Validator.validate_value("not a list", :reasoning_chain)
    end
  end
  
  describe "composite type validation" do
    test "validates lists" do
      list_type = {:list, :string}
      strings = ["a", "b", "c"]
      assert {:ok, ^strings} = Validator.validate_value(strings, list_type)
      
      assert {:error, _} = Validator.validate_value([1, 2, 3], list_type)
    end
    
    test "validates nested lists" do
      nested_type = {:list, {:list, :integer}}
      nested_list = [[1, 2], [3, 4], [5, 6]]
      assert {:ok, ^nested_list} = Validator.validate_value(nested_list, nested_type)
    end
    
    test "validates dictionaries" do
      dict_type = {:dict, :string, :integer}
      dict = %{"a" => 1, "b" => 2}
      assert {:ok, ^dict} = Validator.validate_value(dict, dict_type)
      
      assert {:error, _} = Validator.validate_value(%{1 => "a"}, dict_type)
    end
    
    test "validates unions" do
      union_type = {:union, [:string, :integer]}
      
      assert {:ok, "hello"} = Validator.validate_value("hello", union_type)
      assert {:ok, 42} = Validator.validate_value(42, union_type)
      assert {:error, _} = Validator.validate_value(3.14, union_type)
    end
  end
  
  describe "constraint validation" do
    test "validates string constraints" do
      constraints = [min_length: 3, max_length: 10]
      
      assert {:ok, "hello"} = Validator.validate_value("hello", :string, constraints)
      assert {:error, _} = Validator.validate_value("hi", :string, constraints)
      assert {:error, _} = Validator.validate_value("this is too long", :string, constraints)
    end
    
    test "validates numeric constraints" do
      constraints = [min: 0, max: 100]
      
      assert {:ok, 50} = Validator.validate_value(50, :integer, constraints)
      assert {:error, _} = Validator.validate_value(-1, :integer, constraints)
      assert {:error, _} = Validator.validate_value(101, :integer, constraints)
    end
    
    test "validates atom constraints" do
      constraints = [one_of: [:red, :green, :blue]]
      
      assert {:ok, :red} = Validator.validate_value(:red, :atom, constraints)
      assert {:error, _} = Validator.validate_value(:yellow, :atom, constraints)
    end
    
    test "validates embedding constraints" do
      constraints = [dimensions: 3]
      
      assert {:ok, [1.0, 2.0, 3.0]} = Validator.validate_value([1.0, 2.0, 3.0], :embedding, constraints)
      assert {:error, _} = Validator.validate_value([1.0, 2.0], :embedding, constraints)
    end
  end
end

defmodule DSPex.Types.SerializerTest do
  use ExUnit.Case
  
  alias DSPex.Types.Serializer
  
  describe "JSON schema generation" do
    test "generates basic type schemas" do
      {:ok, schema} = Serializer.serialize("test", :string, :json_schema)
      assert schema.type == "string"
      
      {:ok, schema} = Serializer.serialize(42, :integer, :json_schema)
      assert schema.type == "integer"
    end
    
    test "generates ML type schemas" do
      {:ok, schema} = Serializer.serialize([1.0, 2.0], :embedding, :json_schema)
      assert schema.type == "array"
      assert schema.items.type == "number"
      
      {:ok, schema} = Serializer.serialize(0.5, :probability, :json_schema)
      assert schema.type == "number"
      assert schema.minimum == 0.0
      assert schema.maximum == 1.0
    end
    
    test "generates composite type schemas" do
      {:ok, schema} = Serializer.serialize(["a", "b"], {:list, :string}, :json_schema)
      assert schema.type == "array"
      assert schema.items.type == "string"
      
      {:ok, schema} = Serializer.serialize(%{"key" => "value"}, {:dict, :string, :string}, :json_schema)
      assert schema.type == "object"
      assert schema.additionalProperties.type == "string"
    end
  end
  
  describe "provider-specific serialization" do
    test "generates OpenAI function schemas" do
      {:ok, schema} = Serializer.serialize("test", :string, :openai_function, description: "Test field")
      assert schema.type == "string"
      assert schema.description == "Test field"
      assert Map.has_key?(schema, :examples)
    end
    
    test "generates Anthropic function schemas" do
      {:ok, schema} = Serializer.serialize("test", :string, :anthropic_function, description: "Test field")
      assert schema.type == "string"
      assert schema.description == "Test field"
      refute Map.has_key?(schema, :examples)  # Anthropic doesn't use examples
    end
  end
  
  describe "constraint application to schemas" do
    test "applies string constraints" do
      constraints = [min_length: 5, max_length: 20, pattern: ~r/^[a-z]+$/]
      {:ok, schema} = Serializer.serialize("test", :string, :json_schema, constraints: constraints)
      
      assert schema.minLength == 5
      assert schema.maxLength == 20
      assert schema.pattern == "^[a-z]+$"
    end
    
    test "applies numeric constraints" do
      constraints = [min: 0, max: 100]
      {:ok, schema} = Serializer.serialize(50, :integer, :json_schema, constraints: constraints)
      
      assert schema.minimum == 0
      assert schema.maximum == 100
    end
  end
end
```

### PERFORMANCE OPTIMIZATION

**Caching and Optimization:**
```elixir
defmodule DSPex.Types.Cache do
  @moduledoc """
  Caching layer for type validation and serialization performance.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_validation_result(value, type, constraints) do
    key = :erlang.phash2({value, type, constraints})
    
    case :ets.lookup(:type_validation_cache, key) do
      [{^key, result, timestamp}] ->
        if fresh?(timestamp) do
          result
        else
          validate_and_cache(value, type, constraints, key)
        end
      
      [] ->
        validate_and_cache(value, type, constraints, key)
    end
  end
  
  def get_serialization_result(value, type, target_format, opts) do
    key = :erlang.phash2({value, type, target_format, opts})
    
    case :ets.lookup(:type_serialization_cache, key) do
      [{^key, result, timestamp}] ->
        if fresh?(timestamp) do
          result
        else
          serialize_and_cache(value, type, target_format, opts, key)
        end
      
      [] ->
        serialize_and_cache(value, type, target_format, opts, key)
    end
  end
  
  @impl true
  def init(_opts) do
    :ets.new(:type_validation_cache, [:named_table, :public, read_concurrency: true])
    :ets.new(:type_serialization_cache, [:named_table, :public, read_concurrency: true])
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_cache, 300_000)  # 5 minutes
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_info(:cleanup_cache, state) do
    cleanup_expired_entries()
    Process.send_after(self(), :cleanup_cache, 300_000)
    {:noreply, state}
  end
  
  defp validate_and_cache(value, type, constraints, key) do
    result = DSPex.Types.Validator.validate_value(value, type, constraints)
    :ets.insert(:type_validation_cache, {key, result, System.monotonic_time()})
    result
  end
  
  defp serialize_and_cache(value, type, target_format, opts, key) do
    result = DSPex.Types.Serializer.serialize(value, type, target_format, opts)
    :ets.insert(:type_serialization_cache, {key, result, System.monotonic_time()})
    result
  end
  
  defp fresh?(timestamp) do
    # Consider entries fresh for 5 minutes
    System.monotonic_time() - timestamp < 300_000_000_000  # 5 minutes in nanoseconds
  end
  
  defp cleanup_expired_entries do
    cutoff = System.monotonic_time() - 300_000_000_000
    
    :ets.select_delete(:type_validation_cache, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    :ets.select_delete(:type_serialization_cache, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the comprehensive type system and validation framework with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/dspex/types/
├── registry.ex              # Type definitions and metadata
├── validator.ex             # Core validation engine
├── serializer.ex            # Multi-target serialization
├── exdantic_adapter.ex      # ExDantic integration
├── ash_integration.ex       # Ash type integration
├── cache.ex                 # Performance caching
└── supervisor.ex            # Type system supervision

test/dspex/types/
├── registry_test.exs        # Type registry tests
├── validator_test.exs       # Validation engine tests
├── serializer_test.exs      # Serialization tests
├── exdantic_adapter_test.exs # ExDantic integration tests
├── ash_integration_test.exs # Ash integration tests
└── performance_test.exs     # Performance and caching tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Type Registry (`lib/dspex/types/registry.ex`)**:
   - Complete type definitions with metadata
   - Support for basic, ML-specific, and composite types
   - Type information lookup and validation
   - Extensible architecture for custom types

2. **Validation Engine (`lib/dspex/types/validator.ex`)**:
   - Comprehensive validation with type coercion
   - Constraint validation for all type categories
   - Error handling with detailed error messages
   - Support for nested and composite type validation

3. **Serialization Engine (`lib/dspex/types/serializer.ex`)**:
   - Multi-target serialization (JSON Schema, OpenAI, Anthropic)
   - Constraint application to target schemas
   - Provider-specific optimizations
   - Performance-optimized serialization paths

4. **ExDantic Integration (`lib/dspex/types/exdantic_adapter.ex`)**:
   - Bridge to ExDantic validation patterns
   - Schema generation for complex validations
   - Runtime validation with ExDantic types
   - Integration with signature system

5. **Ash Integration (`lib/dspex/types/ash_integration.ex`)**:
   - Automatic Ash attribute generation
   - Constraint conversion between systems
   - Resource attribute macro support
   - Integration with Ash data layers

### QUALITY REQUIREMENTS:

- **Performance**: Efficient validation and caching for high-throughput scenarios
- **Accuracy**: Precise type checking and constraint validation
- **Extensibility**: Easy addition of new types and target formats
- **Integration**: Seamless integration with ExDantic and Ash patterns
- **Error Handling**: Clear, actionable error messages for validation failures
- **Documentation**: Comprehensive documentation for all public APIs
- **Testing**: Complete test coverage for all type scenarios

### INTEGRATION POINTS:

- Must integrate with signature system for field validation
- Should support adapter pattern type conversion requirements
- Must provide Ash resource attribute generation
- Should enable ExDantic schema creation
- Must support provider-specific serialization formats

### SUCCESS CRITERIA:

1. All basic and ML-specific types validate correctly
2. Composite types handle nested validation properly
3. Constraint validation works for all supported constraints
4. Serialization produces correct schemas for all targets
5. ExDantic integration provides proper validation
6. Ash integration generates correct attributes
7. Performance meets requirements with caching
8. Error messages are clear and actionable
9. All test scenarios pass with comprehensive coverage
10. Integration with other system components works seamlessly

This type system provides the critical validation and serialization infrastructure that ensures data integrity and compatibility across the entire DSPy-Ash integration.