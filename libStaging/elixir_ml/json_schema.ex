defmodule ElixirML.JsonSchema do
  @moduledoc """
  Advanced JSON Schema generation with provider-specific optimizations.

  Provides comprehensive JSON Schema generation capabilities specifically optimized
  for ML use cases and LLM providers. Supports:

  - Provider-specific optimizations (OpenAI, Anthropic, Groq)
  - ML-native type conversion and constraints  
  - Schema flattening and enhancement
  - OpenAPI compatibility
  - Schema merging and validation

  This module consolidates the best features from Elixact's JSON Schema
  generation with ElixirML's ML-specific type system.
  """

  alias ElixirML.Runtime

  @type json_schema :: map()
  @type provider :: :openai | :anthropic | :groq | atom()
  @type optimization_opts :: [
          provider: provider(),
          flatten: boolean(),
          enhance_descriptions: boolean(),
          add_examples: boolean(),
          strict_mode: boolean()
        ]

  @doc """
  Generate JSON schema from ElixirML schema with provider optimizations.

  ## Examples

      iex> schema = ElixirML.Runtime.create_schema([{:name, :string, required: true}])
      iex> json_schema = ElixirML.JsonSchema.generate(schema, provider: :openai)
      iex> json_schema["x-openai-optimized"]
      true

  ## Options

  - `:provider` - Target LLM provider for optimization
  - `:flatten` - Flatten nested schema references  
  - `:enhance_descriptions` - Add/improve field descriptions
  - `:add_examples` - Include example values
  - `:strict_mode` - Enable strict validation rules
  """
  @spec generate(Runtime.t() | module(), optimization_opts()) :: json_schema()
  def generate(schema_or_module, opts \\ [])

  def generate(%Runtime{} = runtime_schema, opts) do
    provider = Keyword.get(opts, :provider, :generic)
    flatten = Keyword.get(opts, :flatten, false)
    enhance_desc = Keyword.get(opts, :enhance_descriptions, true)
    add_examples = Keyword.get(opts, :add_examples, false)

    # Generate base JSON schema
    base_schema = runtime_to_json_schema(runtime_schema)

    # Apply transformations
    base_schema
    |> maybe_flatten_schema(flatten)
    |> maybe_enhance_descriptions(enhance_desc)
    |> ensure_required_array_sorted()
    |> optimize_for_provider(provider)
    |> maybe_add_examples(add_examples, opts[:examples])
  end

  def generate(schema_module, opts) when is_atom(schema_module) do
    # Handle compiled schema modules
    base_schema = schema_module.to_json_schema()
    provider = Keyword.get(opts, :provider, :generic)

    base_schema
    |> apply_ml_type_optimizations()
    |> ensure_required_array_sorted()
    |> optimize_for_provider(provider)
  end

  @doc """
  Optimize JSON schema for specific LLM provider.

  ## Examples

      iex> schema = %{"type" => "object", "properties" => %{}}
      iex> optimized = ElixirML.JsonSchema.optimize_for_provider(schema, :openai)
      iex> optimized["additionalProperties"]
      false
  """
  @spec optimize_for_provider(json_schema(), provider()) :: json_schema()
  def optimize_for_provider(schema, provider)

  def optimize_for_provider(schema, :openai) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array_sorted()
    |> remove_unsupported_formats([:date, :time, :email])
    |> Map.put("x-openai-optimized", true)
  end

  def optimize_for_provider(schema, :anthropic) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array_sorted()
    |> remove_unsupported_formats([:uri, :uuid])
    |> ensure_object_properties()
    |> enhance_descriptions()
    |> Map.put("x-anthropic-optimized", true)
  end

  def optimize_for_provider(schema, :groq) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array_sorted()
    |> Map.put("x-groq-optimized", true)
  end

  def optimize_for_provider(schema, _provider), do: schema

  @doc """
  Flatten schema by inlining $ref definitions.

  ## Examples

      iex> nested = %{
      ...>   "properties" => %{"user" => %{"$ref" => "#/definitions/User"}},
      ...>   "definitions" => %{"User" => %{"type" => "object"}}
      ...> }
      iex> flattened = ElixirML.JsonSchema.flatten_schema(nested)
      iex> flattened["properties"]["user"]["type"]
      "object"
  """
  @spec flatten_schema(json_schema()) :: json_schema()
  def flatten_schema(schema) do
    case Map.get(schema, "definitions") do
      nil ->
        schema

      definitions ->
        flattened_props = flatten_properties(schema["properties"] || %{}, definitions)

        schema
        |> Map.put("properties", flattened_props)
        |> Map.delete("definitions")
    end
  end

  @doc """
  Enhance schema descriptions for better LLM understanding.

  ## Examples

      iex> schema = %{
      ...>   "properties" => %{
      ...>     "field1" => %{"type" => "string"},
      ...>     "field2" => %{"type" => "string", "description" => ""}
      ...>   }
      ...> }
      iex> enhanced = ElixirML.JsonSchema.enhance_descriptions(schema)
      iex> String.contains?(enhanced["properties"]["field1"]["description"], "field1")
      true
  """
  @spec enhance_descriptions(json_schema()) :: json_schema()
  def enhance_descriptions(schema) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        enhanced_properties =
          Enum.reduce(properties, %{}, fn {key, prop}, acc ->
            enhanced_prop = enhance_property_description(prop, key)
            Map.put(acc, key, enhanced_prop)
          end)

        Map.put(schema, "properties", enhanced_properties)
    end
  end

  @doc """
  Remove unsupported format specifications from schema.

  ## Examples

      iex> schema = %{
      ...>   "properties" => %{
      ...>     "date" => %{"type" => "string", "format" => "date"}
      ...>   }
      ...> }
      iex> cleaned = ElixirML.JsonSchema.remove_unsupported_formats(schema, [:date])
      iex> Map.has_key?(cleaned["properties"]["date"], "format")
      false
  """
  @spec remove_unsupported_formats(json_schema(), [atom()]) :: json_schema()
  def remove_unsupported_formats(schema, unsupported_formats) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        cleaned_properties =
          Enum.reduce(properties, %{}, fn {key, prop}, acc ->
            cleaned_prop = remove_format_if_unsupported(prop, unsupported_formats)
            Map.put(acc, key, cleaned_prop)
          end)

        Map.put(schema, "properties", cleaned_properties)
    end
  end

  @doc """
  Validate JSON schema structure and format.

  ## Examples

      iex> valid_schema = %{"type" => "object", "properties" => %{}}
      iex> {:ok, _} = ElixirML.JsonSchema.validate_json_schema(valid_schema)

      iex> invalid_schema = %{"type" => "invalid", "properties" => "not_object"}
      iex> {:error, _} = ElixirML.JsonSchema.validate_json_schema(invalid_schema)
  """
  @spec validate_json_schema(json_schema()) :: {:ok, json_schema()} | {:error, String.t()}
  def validate_json_schema(schema) when is_map(schema) do
    with :ok <- validate_required_fields(schema),
         :ok <- validate_type_field(schema),
         :ok <- validate_properties_field(schema) do
      {:ok, schema}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_json_schema(_), do: {:error, "Schema must be a map"}

  @doc """
  Convert to OpenAPI 3.0 compatible schema format.

  ## Examples

      iex> runtime_schema = ElixirML.Runtime.create_schema([{:id, :string, required: true}])
      iex> openapi = ElixirML.JsonSchema.to_openapi_schema(runtime_schema)
      iex> openapi["type"]
      "object"
  """
  @spec to_openapi_schema(Runtime.t(), keyword()) :: json_schema()
  def to_openapi_schema(%Runtime{} = runtime_schema, opts \\ []) do
    version = Keyword.get(opts, :version, "3.0")

    base_schema = runtime_to_json_schema(runtime_schema)

    case version do
      "3.0" -> add_openapi_3_extensions(base_schema)
      _ -> base_schema
    end
  end

  @doc """
  Add examples to schema properties.

  ## Examples

      iex> schema = %{
      ...>   "properties" => %{"name" => %{"type" => "string"}}
      ...> }
      iex> with_examples = ElixirML.JsonSchema.add_examples(schema, %{"name" => "Alice"})
      iex> with_examples["properties"]["name"]["example"]
      "Alice"
  """
  @spec add_examples(json_schema(), map()) :: json_schema()
  def add_examples(schema, examples) when is_map(examples) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        enhanced_properties =
          Enum.reduce(properties, %{}, fn {key, prop}, acc ->
            case Map.get(examples, key) do
              nil -> Map.put(acc, key, prop)
              example -> Map.put(acc, key, Map.put(prop, "example", example))
            end
          end)

        Map.put(schema, "properties", enhanced_properties)
    end
  end

  @doc """
  Merge multiple JSON schemas into one.

  ## Examples

      iex> schema1 = %{"type" => "object", "properties" => %{"a" => %{"type" => "string"}}}
      iex> schema2 = %{"type" => "object", "properties" => %{"b" => %{"type" => "integer"}}}
      iex> {:ok, merged} = ElixirML.JsonSchema.merge_schemas([schema1, schema2])
      iex> Map.has_key?(merged["properties"], "a") and Map.has_key?(merged["properties"], "b")
      true
  """
  @spec merge_schemas([json_schema()]) :: {:ok, json_schema()} | {:error, String.t()}
  def merge_schemas(schemas) when is_list(schemas) and length(schemas) > 0 do
    try do
      merged = Enum.reduce(schemas, %{}, &merge_two_schemas/2)
      {:ok, merged}
    rescue
      e -> {:error, "Schema merge conflict: #{Exception.message(e)}"}
    end
  end

  def merge_schemas([]), do: {:error, "Cannot merge empty schema list"}

  # Private implementation functions

  defp runtime_to_json_schema(%Runtime{} = runtime_schema) do
    properties = generate_properties_from_runtime(runtime_schema.fields)
    required_fields = get_required_fields_from_runtime(runtime_schema.fields)

    base_schema = %{
      "type" => "object",
      "properties" => properties,
      "required" => required_fields,
      "additionalProperties" => false
    }

    base_schema
    |> add_schema_title(runtime_schema)
    |> add_schema_description(runtime_schema)
  end

  defp generate_properties_from_runtime(fields) when is_map(fields) do
    Enum.reduce(fields, %{}, fn {name, field_def}, acc ->
      property = %{
        "type" => json_type_for_ml_type(field_def.type),
        "description" => field_def.description || ""
      }

      property = add_ml_type_constraints(property, field_def)

      Map.put(acc, to_string(name), property)
    end)
  end

  defp get_required_fields_from_runtime(fields) when is_map(fields) do
    fields
    |> Enum.filter(fn {_name, field_def} -> field_def.required end)
    |> Enum.map(fn {name, _field_def} -> to_string(name) end)
    # Sort to ensure consistent ordering
    |> Enum.sort()
  end

  defp add_schema_title(schema, %Runtime{title: title}) when is_binary(title) do
    Map.put(schema, "title", title)
  end

  defp add_schema_title(schema, %Runtime{name: name}) when is_binary(name) do
    Map.put(schema, "title", name)
  end

  defp add_schema_title(schema, _), do: schema

  defp add_schema_description(schema, %Runtime{metadata: %{description: desc}})
       when is_binary(desc) do
    Map.put(schema, "description", desc)
  end

  defp add_schema_description(schema, _), do: schema

  defp add_ml_type_constraints(property, field_def) do
    case field_def.type do
      :embedding ->
        dimensions = get_in(field_def.constraints, [:dimensions]) || 768

        Map.merge(property, %{
          "type" => "array",
          "items" => %{"type" => "number"},
          "minItems" => dimensions,
          "maxItems" => dimensions
        })

      :probability ->
        Map.merge(property, %{
          "type" => "number",
          "minimum" => 0.0,
          "maximum" => 1.0
        })

      :confidence_score ->
        Map.merge(property, %{
          "type" => "number",
          "minimum" => 0.0
        })

      :token_list ->
        Map.merge(property, %{
          "type" => "array",
          "items" => %{"type" => ["string", "integer"]}
        })

      :reasoning_chain ->
        Map.merge(property, %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "step" => %{"type" => "string"},
              "reasoning" => %{"type" => "string"}
            },
            "required" => ["step", "reasoning"]
          }
        })

      _ ->
        property
    end
  end

  defp json_type_for_ml_type(:embedding), do: "array"
  defp json_type_for_ml_type(:tensor), do: "array"
  defp json_type_for_ml_type(:token_list), do: "array"
  defp json_type_for_ml_type(:probability), do: "number"
  defp json_type_for_ml_type(:confidence_score), do: "number"
  defp json_type_for_ml_type(:model_response), do: "object"
  defp json_type_for_ml_type(:reasoning_chain), do: "array"
  defp json_type_for_ml_type(:attention_weights), do: "array"
  defp json_type_for_ml_type(:string), do: "string"
  defp json_type_for_ml_type(:integer), do: "integer"
  defp json_type_for_ml_type(:float), do: "number"
  defp json_type_for_ml_type(:boolean), do: "boolean"
  defp json_type_for_ml_type(:map), do: "object"
  defp json_type_for_ml_type(:list), do: "array"
  defp json_type_for_ml_type(:choice), do: "string"
  defp json_type_for_ml_type(_), do: "string"

  defp apply_ml_type_optimizations(schema) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        optimized_props =
          properties
          |> Enum.map(fn {key, prop} -> {key, optimize_ml_property_type(prop)} end)
          |> Map.new()

        Map.put(schema, "properties", optimized_props)
    end
  end

  defp optimize_ml_property_type(%{"x-elixir-type" => :embedding} = prop) do
    dimension = get_in(prop, ["x-constraints", "dimension"]) || 768

    Map.merge(prop, %{
      "type" => "array",
      "items" => %{"type" => "number"},
      "minItems" => dimension,
      "maxItems" => dimension
    })
  end

  defp optimize_ml_property_type(%{"x-elixir-type" => :probability} = prop) do
    Map.merge(prop, %{
      "type" => "number",
      "minimum" => 0.0,
      "maximum" => 1.0
    })
  end

  defp optimize_ml_property_type(prop), do: prop

  defp maybe_flatten_schema(schema, true), do: flatten_schema(schema)
  defp maybe_flatten_schema(schema, false), do: schema

  defp maybe_enhance_descriptions(schema, true), do: enhance_descriptions(schema)
  defp maybe_enhance_descriptions(schema, false), do: schema

  defp maybe_add_examples(schema, true, examples) when is_map(examples) do
    add_examples(schema, examples)
  end

  defp maybe_add_examples(schema, _, _), do: schema

  defp flatten_properties(properties, definitions) when is_map(properties) do
    Enum.reduce(properties, %{}, fn {key, prop}, acc ->
      flattened_prop = resolve_references(prop, definitions)
      Map.put(acc, key, flattened_prop)
    end)
  end

  defp resolve_references(%{"$ref" => ref} = _prop, definitions) do
    case extract_definition_name(ref) do
      {:ok, def_name} ->
        case Map.get(definitions, def_name) do
          # Fallback
          nil -> %{"type" => "object"}
          definition -> definition
        end

      {:error, _} ->
        %{"type" => "object"}
    end
  end

  defp resolve_references(prop, _definitions), do: prop

  defp extract_definition_name("#/definitions/" <> name), do: {:ok, name}
  defp extract_definition_name(_), do: {:error, "Invalid reference format"}

  defp enhance_property_description(prop, field_name) do
    case Map.get(prop, "description") do
      nil -> Map.put(prop, "description", "Field: #{field_name}")
      "" -> Map.put(prop, "description", "Field: #{field_name}")
      existing -> Map.put(prop, "description", existing)
    end
  end

  defp remove_format_if_unsupported(prop, unsupported_formats) do
    case Map.get(prop, "format") do
      format when is_atom(format) ->
        if format in unsupported_formats do
          Map.delete(prop, "format")
        else
          prop
        end

      format when is_binary(format) ->
        format_atom = String.to_existing_atom(format)

        if format_atom in unsupported_formats do
          Map.delete(prop, "format")
        else
          prop
        end

      _ ->
        prop
    end
  rescue
    # Handle case where string can't be converted to existing atom
    ArgumentError -> prop
  end

  defp ensure_required_array_sorted(schema) do
    case Map.get(schema, "required") do
      nil -> Map.put(schema, "required", [])
      list when is_list(list) -> Map.put(schema, "required", Enum.sort(list))
      _ -> Map.put(schema, "required", [])
    end
  end

  defp ensure_object_properties(schema) do
    case Map.get(schema, "type") do
      "object" ->
        case Map.get(schema, "properties") do
          nil -> Map.put(schema, "properties", %{})
          _ -> schema
        end

      _ ->
        schema
    end
  end

  defp validate_required_fields(schema) do
    if Map.has_key?(schema, "type") do
      :ok
    else
      {:error, "Schema missing required 'type' field"}
    end
  end

  defp validate_type_field(schema) do
    case Map.get(schema, "type") do
      type when type in ["object", "array", "string", "number", "integer", "boolean", "null"] ->
        :ok

      _ ->
        {:error, "Invalid type field value"}
    end
  end

  defp validate_properties_field(schema) do
    case Map.get(schema, "properties") do
      nil -> :ok
      props when is_map(props) -> :ok
      _ -> {:error, "Properties field must be an object"}
    end
  end

  defp add_openapi_3_extensions(schema) do
    # Add example if possible
    example = generate_example_from_schema(schema)

    schema
    |> Map.put("example", example)
    |> Map.put("x-openapi-version", "3.0")
  end

  defp generate_example_from_schema(%{"properties" => properties}) when is_map(properties) do
    Enum.reduce(properties, %{}, fn {key, prop}, acc ->
      example_value = generate_example_value(prop)
      Map.put(acc, key, example_value)
    end)
  end

  defp generate_example_from_schema(_), do: %{}

  defp generate_example_value(%{"type" => "string"}), do: "example"
  defp generate_example_value(%{"type" => "integer"}), do: 42
  defp generate_example_value(%{"type" => "number"}), do: 3.14
  defp generate_example_value(%{"type" => "boolean"}), do: true
  defp generate_example_value(%{"type" => "array"}), do: []
  defp generate_example_value(%{"type" => "object"}), do: %{}
  defp generate_example_value(_), do: nil

  defp merge_two_schemas(schema1, schema2) do
    merged_properties =
      merge_properties(
        Map.get(schema1, "properties", %{}),
        Map.get(schema2, "properties", %{})
      )

    merged_required =
      merge_required_fields(
        Map.get(schema1, "required", []),
        Map.get(schema2, "required", [])
      )

    %{
      "type" => "object",
      "properties" => merged_properties,
      "required" => merged_required,
      "additionalProperties" => false
    }
  end

  defp merge_properties(props1, props2) do
    # Check for conflicts
    common_keys = MapSet.intersection(MapSet.new(Map.keys(props1)), MapSet.new(Map.keys(props2)))

    Enum.each(common_keys, fn key ->
      type1 = get_in(props1, [key, "type"])
      type2 = get_in(props2, [key, "type"])

      if type1 != type2 do
        raise "Type conflict for field '#{key}': #{type1} vs #{type2}"
      end
    end)

    Map.merge(props1, props2)
  end

  defp merge_required_fields(req1, req2) do
    (req1 ++ req2)
    |> Enum.uniq()
  end
end
