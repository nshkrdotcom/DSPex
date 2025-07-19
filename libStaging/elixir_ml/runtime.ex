defmodule ElixirML.Runtime do
  @moduledoc """
  Enhanced runtime schema creation with ML-specific types and variable integration.

  Combines the best of Elixact's runtime capabilities with ElixirML's
  ML-native types and variable system integration. Provides:

  - Dynamic schema creation for teleprompters
  - Pydantic-style create_model patterns
  - Schema inference from examples
  - Provider-specific optimization
  - Variable extraction for optimization
  - Type adapters for single-value validation
  """

  alias ElixirML.Schema.Types
  alias ElixirML.Schema.ValidationError

  @enforce_keys [:fields]
  defstruct [
    :name,
    :title,
    :fields,
    :validations,
    :transforms,
    :metadata,
    :provider_config
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          title: String.t() | nil,
          fields: %{atom() => field_definition()},
          validations: list(),
          transforms: list(),
          metadata: map(),
          provider_config: map() | nil
        }

  @type field_definition :: %{
          type: atom(),
          required: boolean(),
          default: term(),
          constraints: map(),
          description: String.t() | nil,
          variable: boolean()
        }

  @type field_spec :: {atom(), atom(), keyword()}

  @doc """
  Create a runtime schema from field definitions.

  ## Examples

      iex> schema = ElixirML.Runtime.create_schema([
      ...>   {:name, :string, required: true, min_length: 2},
      ...>   {:confidence, :probability, default: 0.5}
      ...> ])
      iex> ElixirML.Runtime.validate(schema, %{name: "Alice", confidence: 0.8})
      {:ok, %{name: "Alice", confidence: 0.8}}
  """
  @spec create_schema([field_spec()], keyword()) :: t()
  def create_schema(fields, opts \\ []) do
    parsed_fields = parse_field_definitions(fields)

    %__MODULE__{
      name: Keyword.get(opts, :name),
      title: Keyword.get(opts, :title),
      fields: parsed_fields,
      validations: Keyword.get(opts, :validations, []),
      transforms: Keyword.get(opts, :transforms, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      provider_config: nil
    }
  end

  @doc """
  Create a schema using Pydantic's create_model pattern.

  ## Examples

      iex> schema = ElixirML.Runtime.create_model("LLMOutput", %{
      ...>   reasoning: {:string, description: "Chain of thought"},
      ...>   answer: {:string, required: true},
      ...>   confidence: {:float, gteq: 0.0, lteq: 1.0}
      ...> })
      iex> schema.name
      "LLMOutput"
  """
  @spec create_model(String.t(), map(), keyword()) :: t()
  def create_model(name, fields, opts \\ []) when is_map(fields) do
    field_list =
      Enum.map(fields, fn {field_name, field_def} ->
        {field_name, parse_pydantic_field(field_def)}
      end)

    %__MODULE__{
      name: name,
      title: Keyword.get(opts, :title, name),
      fields: Map.new(field_list),
      validations: Keyword.get(opts, :validations, []),
      transforms: Keyword.get(opts, :transforms, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      provider_config: nil
    }
  end

  @doc """
  Infer schema from example data.

  ## Examples

      iex> examples = [
      ...>   %{name: "Alice", age: 30, score: 0.95},
      ...>   %{name: "Bob", age: 25, score: 0.88}
      ...> ]
      iex> schema = ElixirML.Runtime.infer_schema(examples)
      iex> Map.has_key?(schema.fields, :name)
      true
  """
  @spec infer_schema([map()], keyword()) :: t()
  def infer_schema(examples, opts \\ []) when is_list(examples) and length(examples) > 0 do
    inferred_fields = infer_fields_from_examples(examples)

    %__MODULE__{
      name: Keyword.get(opts, :name),
      title: Keyword.get(opts, :title, "Inferred Schema"),
      fields: inferred_fields,
      validations: [],
      transforms: [],
      metadata: %{
        inferred_from: length(examples),
        created_at: DateTime.utc_now()
      },
      provider_config: nil
    }
  end

  @doc """
  Merge multiple schemas into one.

  ## Examples

      iex> schema1 = ElixirML.Runtime.create_schema([{:input, :string, required: true}])
      iex> schema2 = ElixirML.Runtime.create_schema([{:output, :string, required: true}])
      iex> merged = ElixirML.Runtime.merge_schemas([schema1, schema2])
      iex> Map.has_key?(merged.fields, :input) and Map.has_key?(merged.fields, :output)
      true
  """
  @spec merge_schemas([t()], keyword()) :: t()
  def merge_schemas(schemas, opts \\ []) when is_list(schemas) do
    merged_fields =
      schemas
      |> Enum.reduce(%{}, fn schema, acc ->
        Map.merge(acc, schema.fields)
      end)

    %__MODULE__{
      name: Keyword.get(opts, :name),
      title: Keyword.get(opts, :title, "Merged Schema"),
      fields: merged_fields,
      validations: Keyword.get(opts, :validations, []),
      transforms: Keyword.get(opts, :transforms, []),
      metadata: %{
        merged_from: length(schemas),
        source_schemas: Enum.map(schemas, & &1.name)
      },
      provider_config: nil
    }
  end

  @doc """
  Validate data against a runtime schema.

  ## Examples

      iex> schema = ElixirML.Runtime.create_schema([{:name, :string, required: true}])
      iex> ElixirML.Runtime.validate(schema, %{name: "Alice"})
      {:ok, %{name: "Alice"}}
  """
  @spec validate(t(), map()) :: {:ok, map()} | {:error, ValidationError.t()}
  def validate(%__MODULE__{} = schema, data) when is_map(data) do
    with {:ok, validated} <- validate_fields(schema, data),
         {:ok, transformed} <- apply_transforms(schema, validated),
         {:ok, final} <- apply_validations(schema, transformed) do
      {:ok, final}
    else
      {:error, reason} ->
        {:error,
         %ValidationError{
           message: reason,
           schema: __MODULE__,
           data: data
         }}
    end
  end

  @doc """
  Extract variables from a runtime schema for optimization.

  ## Examples

      iex> schema = ElixirML.Runtime.create_schema([
      ...>   {:name, :string, required: true},
      ...>   {:temperature, :float, variable: true, range: {0.0, 2.0}}
      ...> ])
      iex> variables = ElixirML.Runtime.extract_variables(schema)
      iex> length(variables)
      1
  """
  @spec extract_variables(t()) :: [field_spec()]
  def extract_variables(%__MODULE__{fields: fields}) do
    fields
    |> Enum.filter(fn {_name, field_def} -> field_def.variable end)
    |> Enum.map(fn {name, field_def} ->
      opts = build_variable_opts(field_def)
      {name, field_def.type, opts}
    end)
  end

  @doc """
  Optimize schema for specific LLM provider.

  ## Examples

      iex> schema = ElixirML.Runtime.create_schema([{:question, :string, required: true}])
      iex> optimized = ElixirML.Runtime.optimize_for_provider(schema, :openai)
      iex> optimized.provider_config.provider
      :openai
  """
  @spec optimize_for_provider(t(), atom()) :: t()
  def optimize_for_provider(%__MODULE__{} = schema, provider) do
    provider_config = get_provider_config(provider)
    %{schema | provider_config: provider_config}
  end

  @doc """
  Generate JSON schema with provider-specific optimizations.

  ## Examples

      iex> schema = ElixirML.Runtime.create_schema([{:question, :string, required: true}])
      iex> json_schema = ElixirML.Runtime.to_json_schema(schema, provider: :openai)
      iex> json_schema["type"]
      "object"
  """
  @spec to_json_schema(t(), keyword()) :: map()
  def to_json_schema(%__MODULE__{} = schema, opts \\ []) do
    provider = Keyword.get(opts, :provider, :default)

    properties = generate_properties(schema.fields)
    required_fields = get_required_fields(schema.fields)

    base_schema = %{
      "type" => "object",
      "properties" => properties,
      "required" => required_fields,
      "additionalProperties" => false
    }

    base_schema
    |> add_schema_metadata(schema)
    |> apply_provider_optimizations(provider)
  end

  @doc """
  Create a type adapter for single-value validation.

  ## Examples

      iex> adapter = ElixirML.Runtime.type_adapter(:embedding, dimensions: 1536)
      iex> ElixirML.Runtime.validate_with_adapter(adapter, [1.0, 2.0, 3.0])
      {:ok, [1.0, 2.0, 3.0]}
  """
  @spec type_adapter(atom(), keyword()) :: t()
  def type_adapter(type, opts \\ []) do
    field_def = %{
      type: type,
      required: true,
      default: nil,
      constraints: extract_constraints_from_opts(type, opts),
      description: Keyword.get(opts, :description),
      variable: false
    }

    %__MODULE__{
      name: "TypeAdapter_#{type}",
      title: "Type Adapter for #{type}",
      fields: %{value: field_def},
      validations: [],
      transforms: [],
      metadata: %{adapter_type: type},
      provider_config: nil
    }
  end

  @doc """
  Validate a single value using a type adapter.

  ## Examples

      iex> adapter = ElixirML.Runtime.type_adapter(:probability)
      iex> ElixirML.Runtime.validate_with_adapter(adapter, 0.5)
      {:ok, 0.5}
  """
  @spec validate_with_adapter(t(), term()) :: {:ok, term()} | {:error, String.t()}
  def validate_with_adapter(%__MODULE__{} = adapter, value) do
    case validate(adapter, %{value: value}) do
      {:ok, %{value: validated_value}} -> {:ok, validated_value}
      {:error, error} -> {:error, error.message}
    end
  end

  # Private implementation functions

  defp parse_field_definitions(fields) do
    Enum.reduce(fields, %{}, fn {name, type, opts}, acc ->
      field_def = %{
        type: type,
        required: Keyword.get(opts, :required, false),
        default: Keyword.get(opts, :default),
        constraints: extract_constraints_from_opts(type, opts),
        description: Keyword.get(opts, :description),
        variable: Keyword.get(opts, :variable, false)
      }

      Map.put(acc, name, field_def)
    end)
  end

  defp parse_pydantic_field({type, opts}) when is_list(opts) do
    %{
      type: type,
      required: Keyword.get(opts, :required, false),
      default: Keyword.get(opts, :default),
      constraints: extract_pydantic_constraints(opts),
      description: Keyword.get(opts, :description),
      variable: false
    }
  end

  defp parse_pydantic_field({type, opts}) when is_map(opts) do
    parse_pydantic_field({type, Map.to_list(opts)})
  end

  defp extract_constraints_from_opts(:float, opts) do
    # Check for explicit range first
    explicit_range = Keyword.get(opts, :range)

    # Get explicit min/max constraints
    min_val = Keyword.get(opts, :gteq) || Keyword.get(opts, :ge) || Keyword.get(opts, :gt)
    max_val = Keyword.get(opts, :lteq) || Keyword.get(opts, :le) || Keyword.get(opts, :lt)

    range =
      if explicit_range do
        explicit_range
      else
        case {min_val, max_val} do
          # Only apply default if NO constraints provided
          {nil, nil} -> {0.0, 1.0}
          # Use explicit constraints when provided
          {min, max} when not is_nil(min) and not is_nil(max) -> {min, max}
          {min, nil} when not is_nil(min) -> {min, 100.0}
          {nil, max} when not is_nil(max) -> {0.0, max}
        end
      end

    %{
      range: range,
      min_value: min_val,
      max_value: max_val
    }
  end

  defp extract_constraints_from_opts(:integer, opts) do
    # Check for explicit range first
    explicit_range = Keyword.get(opts, :range)

    # Get explicit min/max constraints
    min_val = Keyword.get(opts, :gteq) || Keyword.get(opts, :gte) || Keyword.get(opts, :gt)
    max_val = Keyword.get(opts, :lteq) || Keyword.get(opts, :lte) || Keyword.get(opts, :lt)

    range =
      if explicit_range do
        explicit_range
      else
        case {min_val, max_val} do
          # Only apply default if NO constraints provided
          {nil, nil} -> {1, 100}
          # Use explicit constraints when provided
          {min, max} when not is_nil(min) and not is_nil(max) -> {min, max}
          {min, nil} when not is_nil(min) -> {min, 1_000_000}
          {nil, max} when not is_nil(max) -> {0, max}
        end
      end

    %{
      range: range,
      min_value: min_val,
      max_value: max_val
    }
  end

  defp extract_constraints_from_opts(:choice, opts) do
    %{
      choices: Keyword.get(opts, :choices, []),
      allow_custom: Keyword.get(opts, :allow_custom, false)
    }
  end

  defp extract_constraints_from_opts(:atom, opts) do
    %{
      choices: Keyword.get(opts, :choices, []),
      allow_custom: Keyword.get(opts, :allow_custom, false)
    }
  end

  defp extract_constraints_from_opts(:string, opts) do
    %{
      min_length: Keyword.get(opts, :min_length),
      max_length: Keyword.get(opts, :max_length),
      pattern: Keyword.get(opts, :pattern)
    }
  end

  defp extract_constraints_from_opts(:embedding, opts) do
    %{
      dimensions: Keyword.get(opts, :dimensions),
      min_items: Keyword.get(opts, :min_items, 1)
    }
  end

  defp extract_constraints_from_opts(_type, _opts), do: %{}

  defp extract_pydantic_constraints(opts) do
    %{
      ge: Keyword.get(opts, :ge),
      le: Keyword.get(opts, :le),
      gt: Keyword.get(opts, :gt),
      lt: Keyword.get(opts, :lt),
      gteq: Keyword.get(opts, :gteq),
      lteq: Keyword.get(opts, :lteq),
      choices: Keyword.get(opts, :choices)
    }
    |> Enum.filter(fn {_k, v} -> not is_nil(v) end)
    |> Map.new()
  end

  defp infer_fields_from_examples(examples) do
    # Take first example as base, then refine with others
    base_fields = infer_fields_from_single_example(hd(examples))

    Enum.reduce(tl(examples), base_fields, fn example, acc ->
      refine_inferred_fields(acc, example)
    end)
  end

  defp infer_fields_from_single_example(example) when is_map(example) do
    Enum.reduce(example, %{}, fn {key, value}, acc ->
      field_def = %{
        type: infer_type(value),
        # Assume required if present in example
        required: true,
        default: nil,
        constraints: infer_constraints(value),
        description: nil,
        variable: false
      }

      Map.put(acc, key, field_def)
    end)
  end

  defp refine_inferred_fields(fields, example) do
    # For now, just ensure all fields from example are present
    # In a full implementation, this would refine type inference
    Enum.reduce(example, fields, fn {key, value}, acc ->
      if Map.has_key?(acc, key) do
        acc
      else
        field_def = %{
          type: infer_type(value),
          # Not required since missing from some examples
          required: false,
          default: nil,
          constraints: infer_constraints(value),
          description: nil,
          variable: false
        }

        Map.put(acc, key, field_def)
      end
    end)
  end

  defp infer_type(value) when is_binary(value), do: :string
  defp infer_type(value) when is_integer(value), do: :integer

  defp infer_type(value) when is_float(value) do
    # Check if it might be a probability
    if value >= 0.0 and value <= 1.0 do
      :probability
    else
      :float
    end
  end

  defp infer_type(value) when is_boolean(value), do: :boolean

  defp infer_type(value) when is_list(value) do
    case value do
      [] ->
        :list

      [first | _] when is_number(first) ->
        # Check if all elements are numbers (potential embedding)
        if Enum.all?(value, &is_number/1) do
          :embedding
        else
          :list
        end

      _ ->
        :list
    end
  end

  defp infer_type(value) when is_map(value), do: :map
  defp infer_type(_value), do: :string

  defp infer_constraints(value) when is_list(value) and length(value) > 0 do
    if Enum.all?(value, &is_number/1) do
      %{dimensions: length(value)}
    else
      %{}
    end
  end

  defp infer_constraints(_value), do: %{}

  defp validate_fields(%__MODULE__{fields: fields}, data) do
    Enum.reduce_while(fields, {:ok, data}, fn {name, field_def}, {:ok, acc_data} ->
      case validate_field(name, field_def, acc_data) do
        {:ok, updated_data} -> {:cont, {:ok, updated_data}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_field(name, field_def, data) do
    value = Map.get(data, name)

    cond do
      is_nil(value) and field_def.required ->
        {:error, "Field #{name} is required"}

      is_nil(value) and not is_nil(field_def.default) ->
        {:ok, Map.put(data, name, field_def.default)}

      is_nil(value) ->
        {:ok, data}

      true ->
        case validate_field_value(value, field_def) do
          {:ok, validated_value} ->
            {:ok, Map.put(data, name, validated_value)}

          {:error, reason} ->
            {:error, "Field #{name}: #{reason}"}
        end
    end
  end

  defp validate_field_value(value, field_def) do
    # First validate the basic type
    case Types.validate_type(value, field_def.type) do
      {:ok, validated} ->
        # Then apply additional constraints
        apply_field_constraints(validated, field_def)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_field_constraints(value, field_def) do
    case field_def.type do
      :float -> validate_numeric_constraints(value, field_def.constraints)
      :integer -> validate_numeric_constraints(value, field_def.constraints)
      :string -> validate_string_constraints(value, field_def.constraints)
      :choice -> validate_choice_constraints(value, field_def.constraints)
      :atom -> validate_choice_constraints(value, field_def.constraints)
      _ -> {:ok, value}
    end
  end

  defp validate_numeric_constraints(value, constraints) do
    cond do
      constraints[:min_value] && value < constraints[:min_value] ->
        {:error, "Value #{value} below minimum #{constraints[:min_value]}"}

      constraints[:max_value] && value > constraints[:max_value] ->
        {:error, "Value #{value} above maximum #{constraints[:max_value]}"}

      constraints[:range] ->
        {min, max} = constraints[:range]

        if value < min or value > max do
          {:error, "Value #{value} outside range #{inspect(constraints[:range])}"}
        else
          {:ok, value}
        end

      true ->
        {:ok, value}
    end
  end

  defp validate_string_constraints(value, constraints) do
    cond do
      constraints[:min_length] && String.length(value) < constraints[:min_length] ->
        {:error, "String too short (minimum #{constraints[:min_length]} characters)"}

      constraints[:max_length] && String.length(value) > constraints[:max_length] ->
        {:error, "String too long (maximum #{constraints[:max_length]} characters)"}

      true ->
        {:ok, value}
    end
  end

  defp validate_choice_constraints(value, constraints) do
    choices = constraints[:choices] || []

    if value in choices or constraints[:allow_custom] do
      {:ok, value}
    else
      {:error, "Value #{inspect(value)} not in allowed choices #{inspect(choices)}"}
    end
  end

  defp apply_transforms(%__MODULE__{transforms: transforms}, data) do
    Enum.reduce_while(transforms, {:ok, data}, fn {_name, transform_fn}, {:ok, acc_data} ->
      case apply_transform(transform_fn, acc_data) do
        {:ok, transformed} -> {:cont, {:ok, transformed}}
        {:error, reason} -> {:halt, {:error, reason}}
        transformed when is_map(transformed) -> {:cont, {:ok, transformed}}
      end
    end)
  end

  defp apply_transform(transform_fn, data) when is_function(transform_fn, 1) do
    transform_fn.(data)
  rescue
    e -> {:error, "Transform failed: #{Exception.message(e)}"}
  end

  defp apply_validations(%__MODULE__{validations: validations}, data) do
    Enum.reduce_while(validations, {:ok, data}, fn {_name, validation_fn}, {:ok, acc_data} ->
      case apply_validation(validation_fn, acc_data) do
        {:ok, _} -> {:cont, {:ok, acc_data}}
        {:error, reason} -> {:halt, {:error, reason}}
        true -> {:cont, {:ok, acc_data}}
        false -> {:halt, {:error, "Validation failed"}}
      end
    end)
  end

  defp apply_validation(validation_fn, data) when is_function(validation_fn, 1) do
    validation_fn.(data)
  rescue
    e -> {:error, "Validation failed: #{Exception.message(e)}"}
  end

  defp build_variable_opts(field_def) do
    base_opts = [
      required: field_def.required,
      description: field_def.description
    ]

    constraint_opts =
      case field_def.type do
        :float -> [range: field_def.constraints[:range], default: field_def.default]
        :integer -> [range: field_def.constraints[:range], default: field_def.default]
        :choice -> [choices: field_def.constraints[:choices], default: field_def.default]
        _ -> [default: field_def.default]
      end

    Keyword.merge(base_opts, constraint_opts)
    |> Enum.filter(fn {_k, v} -> not is_nil(v) end)
  end

  defp get_provider_config(:openai) do
    %{
      provider: :openai,
      flatten_nested: true,
      enhance_descriptions: true,
      strict_schema: true
    }
  end

  defp get_provider_config(:anthropic) do
    %{
      provider: :anthropic,
      preserve_structure: true,
      detailed_descriptions: true,
      tool_use_optimized: true
    }
  end

  defp get_provider_config(:groq) do
    %{
      provider: :groq,
      performance_optimized: true,
      simple_schema: true
    }
  end

  defp get_provider_config(_provider) do
    %{
      provider: :default,
      standard_schema: true
    }
  end

  defp generate_properties(fields) do
    Enum.reduce(fields, %{}, fn {name, field_def}, acc ->
      property = %{
        "type" => json_type_for(field_def.type),
        "description" => field_def.description || ""
      }

      property = add_type_specific_constraints(property, field_def)
      property = add_general_constraints(property, field_def)

      Map.put(acc, to_string(name), property)
    end)
  end

  defp get_required_fields(fields) do
    fields
    |> Enum.filter(fn {_name, field_def} -> field_def.required end)
    |> Enum.map(fn {name, _field_def} -> to_string(name) end)
  end

  defp add_schema_metadata(schema, runtime_schema) do
    metadata = %{}

    metadata =
      if runtime_schema.title,
        do: Map.put(metadata, "title", runtime_schema.title),
        else: metadata

    metadata =
      if runtime_schema.name, do: Map.put(metadata, "name", runtime_schema.name), else: metadata

    Map.merge(schema, metadata)
  end

  defp apply_provider_optimizations(schema, :openai) do
    # OpenAI prefers flattened schemas without definitions
    schema
    |> Map.put("strict", true)
    |> Map.put("x-openai-optimized", true)
    |> maybe_flatten_schema()
  end

  defp apply_provider_optimizations(schema, :anthropic) do
    # Anthropic prefers detailed descriptions and structured schemas
    schema
    |> Map.put("x-anthropic-optimized", true)
    |> enhance_descriptions()
  end

  defp apply_provider_optimizations(schema, :groq) do
    # Groq optimizations
    schema
    |> Map.put("x-groq-optimized", true)
  end

  defp apply_provider_optimizations(schema, _provider), do: schema

  defp maybe_flatten_schema(schema) do
    # For now, just ensure no definitions section
    Map.delete(schema, "definitions")
  end

  defp enhance_descriptions(schema) do
    # Enhance property descriptions for better Anthropic tool use
    properties =
      case schema["properties"] do
        nil ->
          %{}

        props ->
          Enum.reduce(props, %{}, fn {key, prop}, acc ->
            enhanced_prop =
              case prop["description"] do
                "" -> Map.put(prop, "description", "Field: #{key}")
                nil -> Map.put(prop, "description", "Field: #{key}")
                desc -> Map.put(prop, "description", desc)
              end

            Map.put(acc, key, enhanced_prop)
          end)
      end

    Map.put(schema, "properties", properties)
  end

  defp add_type_specific_constraints(property, field_def) do
    case field_def.type do
      :embedding ->
        Map.merge(property, %{
          "type" => "array",
          "items" => %{"type" => "number"},
          "minItems" => 1
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
            }
          }
        })

      _ ->
        property
    end
  end

  defp add_general_constraints(property, field_def) do
    constraints = field_def.constraints || %{}

    property
    |> add_string_constraints(constraints)
    |> add_numeric_constraints(constraints)
    |> add_array_constraints(constraints)
  end

  defp add_string_constraints(property, constraints) do
    property
    |> maybe_add_constraint("minLength", constraints[:min_length])
    |> maybe_add_constraint("maxLength", constraints[:max_length])
    |> maybe_add_constraint("pattern", constraints[:pattern])
  end

  defp add_numeric_constraints(property, constraints) do
    property
    |> maybe_add_constraint("minimum", constraints[:min_value])
    |> maybe_add_constraint("maximum", constraints[:max_value])
    |> maybe_add_range_constraints(constraints[:range])
  end

  defp add_array_constraints(property, constraints) do
    property
    |> maybe_add_constraint("minItems", constraints[:min_items])
    |> maybe_add_constraint("maxItems", constraints[:max_items])
  end

  defp maybe_add_constraint(property, _key, nil), do: property
  defp maybe_add_constraint(property, key, value), do: Map.put(property, key, value)

  defp maybe_add_range_constraints(property, nil), do: property

  defp maybe_add_range_constraints(property, {min, max}) do
    property
    |> Map.put("minimum", min)
    |> Map.put("maximum", max)
  end

  defp json_type_for(:embedding), do: "array"
  defp json_type_for(:tensor), do: "array"
  defp json_type_for(:token_list), do: "array"
  defp json_type_for(:probability), do: "number"
  defp json_type_for(:confidence_score), do: "number"
  defp json_type_for(:model_response), do: "object"
  defp json_type_for(:reasoning_chain), do: "array"
  defp json_type_for(:attention_weights), do: "array"
  defp json_type_for(:string), do: "string"
  defp json_type_for(:integer), do: "integer"
  defp json_type_for(:float), do: "number"
  defp json_type_for(:boolean), do: "boolean"
  defp json_type_for(:map), do: "object"
  defp json_type_for(:list), do: "array"
  defp json_type_for(:choice), do: "string"
  defp json_type_for(_), do: "string"
end
