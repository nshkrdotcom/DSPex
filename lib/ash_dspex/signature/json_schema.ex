defmodule AshDSPex.Signature.JsonSchema do
  @moduledoc """
  JSON Schema generation for signature compatibility with various AI providers.

  This module generates JSON schemas from signature definitions, enabling seamless
  integration with AI providers that support function calling or structured data
  validation (OpenAI, Anthropic, Google, etc.).

  ## Supported Providers

  - `:openai` - OpenAI Function Calling format
  - `:anthropic` - Anthropic Tool schema format  
  - `:generic` - Standard JSON Schema Draft 7

  ## Generated Schema Features

  - Full type mapping from signature types to JSON Schema types
  - Required field specifications
  - Constraint validation (ranges, patterns, etc.)
  - Nested object and array support
  - Union type handling with oneOf
  - Provider-specific optimizations

  ## Usage

      defmodule QA do
        use AshDSPex.Signature
        signature question: :string -> answer: :string
      end

      # Generate OpenAI function calling schema
      schema = QA.to_json_schema(:openai)
      
      # Generate generic JSON Schema
      schema = QA.to_json_schema(:generic)

  ## Schema Structure

  The generated schemas follow the respective provider formats:

  ### OpenAI Function Calling
      %{
        type: "object",
        properties: %{...},
        required: [...],
        additionalProperties: false
      }

  ### Anthropic Tools  
      %{
        input_schema: %{
          type: "object", 
          properties: %{...},
          required: [...]
        }
      }

  ### Generic JSON Schema
      %{
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        type: "object",
        properties: %{...},
        required: [...]
      }
  """

  alias AshDSPex.Signature.TypeParser

  @doc """
  Generates a JSON schema for the given signature and provider.

  The signature parameter should be the compiled signature metadata
  (from `__signature__/0`). The provider determines the output format.

  ## Examples

      iex> signature = %{
      ...>   inputs: [{:question, :string, []}],
      ...>   outputs: [{:answer, :string, []}],
      ...>   module: TestSignature
      ...> }
      iex> schema = AshDSPex.Signature.JsonSchema.generate(signature, :openai)
      iex> schema.type
      "object"
      iex> Map.has_key?(schema.properties, :question)
      true
  """
  @spec generate(
          %{inputs: list(), outputs: list(), module: module()},
          :openai | :anthropic | :generic
        ) :: map()
  def generate(signature, provider \\ :openai)

  def generate(%{inputs: inputs, outputs: outputs} = signature, :openai) do
    all_fields = inputs ++ outputs
    properties = generate_properties(all_fields)
    required = get_required_fields(all_fields)

    %{
      type: "object",
      properties: properties,
      required: required,
      additionalProperties: false,
      description: generate_description(signature)
    }
  end

  def generate(%{inputs: inputs, outputs: _outputs} = signature, :anthropic) do
    input_properties = generate_properties(inputs)
    input_required = get_required_fields(inputs)

    %{
      input_schema: %{
        type: "object",
        properties: input_properties,
        required: input_required,
        additionalProperties: false
      },
      description: generate_description(signature)
    }
  end

  def generate(%{inputs: inputs, outputs: outputs} = signature, :generic) do
    all_fields = inputs ++ outputs
    properties = generate_properties(all_fields)
    required = get_required_fields(all_fields)

    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      type: "object",
      title: generate_title(signature),
      description: generate_description(signature),
      properties: properties,
      required: required,
      additionalProperties: false
    }
  end

  def generate(signature, unsupported_provider) do
    raise """
    Unsupported provider: #{inspect(unsupported_provider)}

    Supported providers: :openai, :anthropic, :generic
    Signature: #{inspect(signature)}
    """
  end

  @doc """
  Generates properties map from field definitions.

  Converts signature field definitions into JSON Schema property definitions
  with appropriate type mappings and constraints.
  """
  @spec generate_properties([{atom(), any(), list()}]) :: map()
  def generate_properties(fields) do
    fields
    |> Enum.map(fn {name, type, constraints} ->
      {name, type_to_json_schema(type, constraints)}
    end)
    |> Map.new()
  end

  @doc """
  Converts a signature type to JSON Schema type definition.

  Handles all supported signature types including basic types, ML-specific types,
  and composite types with proper constraint mapping.

  ## Examples

      iex> AshDSPex.Signature.JsonSchema.type_to_json_schema(:string, [])
      %{type: "string"}

      iex> AshDSPex.Signature.JsonSchema.type_to_json_schema({:list, :string}, [])
      %{type: "array", items: %{type: "string"}}

      iex> AshDSPex.Signature.JsonSchema.type_to_json_schema(:probability, [])
      %{type: "number", minimum: 0.0, maximum: 1.0, description: "Probability value between 0.0 and 1.0"}
  """
  @spec type_to_json_schema(any(), list()) :: map()
  def type_to_json_schema(:string, constraints) do
    base_schema = %{type: "string"}
    apply_string_constraints(base_schema, constraints)
  end

  def type_to_json_schema(:integer, constraints) do
    base_schema = %{type: "integer"}
    apply_numeric_constraints(base_schema, constraints)
  end

  def type_to_json_schema(:float, constraints) do
    base_schema = %{type: "number"}
    apply_numeric_constraints(base_schema, constraints)
  end

  def type_to_json_schema(:boolean, _constraints) do
    %{type: "boolean"}
  end

  def type_to_json_schema(:atom, constraints) do
    case Keyword.get(constraints, :enum) do
      nil -> %{type: "string", description: "Atom value"}
      enum_values -> %{type: "string", enum: Enum.map(enum_values, &to_string/1)}
    end
  end

  def type_to_json_schema(:any, _constraints) do
    %{description: "Any value type"}
  end

  def type_to_json_schema(:map, _constraints) do
    %{type: "object", additionalProperties: true}
  end

  # ML-specific types
  def type_to_json_schema(:embedding, constraints) do
    base_schema = %{
      type: "array",
      items: %{type: "number"},
      description: "Vector embedding"
    }

    apply_array_constraints(base_schema, constraints)
  end

  def type_to_json_schema(:probability, constraints) do
    base_schema = %{
      type: "number",
      minimum: 0.0,
      maximum: 1.0,
      description: "Probability value between 0.0 and 1.0"
    }

    apply_numeric_constraints(base_schema, constraints)
  end

  def type_to_json_schema(:confidence_score, constraints) do
    base_schema = %{
      type: "number",
      minimum: 0.0,
      maximum: 1.0,
      description: "Confidence score between 0.0 and 1.0"
    }

    apply_numeric_constraints(base_schema, constraints)
  end

  def type_to_json_schema(:reasoning_chain, constraints) do
    base_schema = %{
      type: "array",
      items: %{type: "string"},
      description: "Step-by-step reasoning chain"
    }

    apply_array_constraints(base_schema, constraints)
  end

  # Composite types
  def type_to_json_schema({:list, inner_type}, constraints) do
    base_schema = %{
      type: "array",
      items: type_to_json_schema(inner_type, [])
    }

    apply_array_constraints(base_schema, constraints)
  end

  def type_to_json_schema({:dict, key_type, value_type}, constraints) do
    base_schema = %{
      type: "object",
      description:
        "Dictionary with #{TypeParser.describe_type(key_type)} keys and #{TypeParser.describe_type(value_type)} values",
      additionalProperties: type_to_json_schema(value_type, [])
    }

    apply_object_constraints(base_schema, constraints)
  end

  def type_to_json_schema({:union, types}, _constraints) when is_list(types) do
    %{
      oneOf: Enum.map(types, &type_to_json_schema(&1, [])),
      description: "Union of #{length(types)} possible types"
    }
  end

  def type_to_json_schema(unknown_type, _constraints) do
    %{
      description: "Unknown type: #{inspect(unknown_type)}"
    }
  end

  @doc """
  Extracts required field names from field definitions.

  Currently treats all fields as required, but the structure supports
  optional fields through constraints in the future.
  """
  @spec get_required_fields([{atom(), any(), list()}]) :: [String.t()]
  def get_required_fields(fields) do
    fields
    |> Enum.reject(fn {_name, _type, constraints} ->
      Keyword.get(constraints, :optional, false)
    end)
    |> Enum.map(fn {name, _type, _constraints} -> to_string(name) end)
  end

  # Private helper functions for constraint application

  defp apply_string_constraints(schema, constraints) do
    schema
    |> maybe_add_constraint(constraints, :min_length, :minLength)
    |> maybe_add_constraint(constraints, :max_length, :maxLength)
    |> maybe_add_constraint(constraints, :pattern, :pattern)
    |> maybe_add_constraint(constraints, :format, :format)
  end

  defp apply_numeric_constraints(schema, constraints) do
    schema
    |> maybe_add_constraint(constraints, :minimum, :minimum)
    |> maybe_add_constraint(constraints, :maximum, :maximum)
    |> maybe_add_constraint(constraints, :multiple_of, :multipleOf)
  end

  defp apply_array_constraints(schema, constraints) do
    schema
    |> maybe_add_constraint(constraints, :min_items, :minItems)
    |> maybe_add_constraint(constraints, :max_items, :maxItems)
    |> maybe_add_constraint(constraints, :unique_items, :uniqueItems)
  end

  defp apply_object_constraints(schema, constraints) do
    schema
    |> maybe_add_constraint(constraints, :min_properties, :minProperties)
    |> maybe_add_constraint(constraints, :max_properties, :maxProperties)
  end

  defp maybe_add_constraint(schema, constraints, constraint_key, json_key) do
    case Keyword.get(constraints, constraint_key) do
      nil -> schema
      value -> Map.put(schema, json_key, value)
    end
  end

  defp generate_description(%{module: module, inputs: inputs, outputs: outputs}) do
    module_name = module |> to_string() |> String.replace("Elixir.", "")
    input_desc = describe_fields(inputs)
    output_desc = describe_fields(outputs)

    "#{module_name} signature: #{input_desc} -> #{output_desc}"
  end

  defp generate_title(%{module: module}) do
    module |> to_string() |> String.replace("Elixir.", "") |> String.replace(".", "_")
  end

  defp describe_fields(fields) do
    fields
    |> Enum.map(fn {name, type, _} ->
      "#{name}: #{TypeParser.describe_type(type)}"
    end)
    |> Enum.join(", ")
  end

  @doc """
  Validates a JSON schema against a known good structure.

  Useful for testing and debugging schema generation.
  """
  @spec validate_schema(map()) :: :ok | {:error, String.t()}
  def validate_schema(%{type: "object", properties: properties, required: required})
      when is_map(properties) and is_list(required) do
    :ok
  end

  def validate_schema(%{input_schema: %{type: "object"}} = _anthropic_schema) do
    :ok
  end

  def validate_schema(schema) do
    {:error, "Invalid schema structure: #{inspect(schema)}"}
  end

  @doc """
  Estimates the complexity of a generated schema.

  Returns a complexity score based on nesting depth, number of properties,
  and type diversity. Useful for performance optimization.
  """
  @spec estimate_complexity(map()) :: integer()
  def estimate_complexity(%{properties: properties} = schema) do
    property_count = map_size(properties)
    max_depth = calculate_max_depth(schema, 0)
    type_diversity = count_unique_types(schema)

    round(property_count + max_depth * 2 + type_diversity)
  end

  def estimate_complexity(_schema), do: 1

  defp calculate_max_depth(%{properties: properties}, current_depth) do
    properties
    |> Map.values()
    |> Enum.map(&calculate_max_depth(&1, current_depth + 1))
    |> Enum.max(fn -> current_depth end)
  end

  defp calculate_max_depth(%{items: items}, current_depth) do
    calculate_max_depth(items, current_depth + 1)
  end

  defp calculate_max_depth(%{oneOf: schemas}, current_depth) when is_list(schemas) do
    schemas
    |> Enum.map(&calculate_max_depth(&1, current_depth + 1))
    |> Enum.max(fn -> current_depth end)
  end

  defp calculate_max_depth(_schema, current_depth), do: current_depth

  defp count_unique_types(schema) do
    schema
    |> extract_all_types([])
    |> Enum.uniq()
    |> length()
  end

  defp extract_all_types(%{type: type} = schema, acc) do
    acc = [type | acc]

    case schema do
      %{properties: properties} ->
        Enum.reduce(properties, acc, fn {_key, prop_schema}, acc ->
          extract_all_types(prop_schema, acc)
        end)

      %{items: items} ->
        extract_all_types(items, acc)

      %{oneOf: schemas} when is_list(schemas) ->
        Enum.reduce(schemas, acc, fn schema, acc ->
          extract_all_types(schema, acc)
        end)

      _ ->
        acc
    end
  end

  defp extract_all_types(_schema, acc), do: acc
end
