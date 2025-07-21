defmodule ElixirML.Schema do
  @moduledoc """
  Enhanced schema system for ElixirML/DSPEx with ML-specific types,
  compile-time optimization, and comprehensive validation.

  Built on Sinter for advanced schema capabilities with native support
  for ML-specific types like embeddings, probabilities, and confidence scores.
  """

  alias ElixirML.Schema.Runtime

  defmacro __using__(_opts) do
    quote do
      import ElixirML.Schema, only: [defschema: 2]
    end
  end

  defmacro defschema(name, do: block) do
    quote do
      defmodule unquote(name) do
        use ElixirML.Schema.Definition
        import ElixirML.Schema.DSL

        unquote(block)

        @before_compile ElixirML.Schema.Compiler
      end
    end
  end

  @doc """
  Create a runtime schema for dynamic validation.

  ## Examples

      iex> schema = ElixirML.Schema.create([
      ...>   {:embedding, :embedding, required: true},
      ...>   {:confidence, :probability, default: 0.5}
      ...> ])
      iex> ElixirML.Schema.validate(schema, %{embedding: [1.0, 2.0, 3.0], confidence: 0.8})
      {:ok, %{embedding: [1.0, 2.0, 3.0], confidence: 0.8}}
  """
  @spec create(list(), keyword()) :: Runtime.t()
  def create(fields, opts \\ []) do
    %Runtime{
      name: Keyword.get(opts, :title),
      fields: fields,
      validations: Keyword.get(opts, :validations, []),
      transforms: Keyword.get(opts, :transforms, []),
      metadata:
        Map.merge(
          %{description: Keyword.get(opts, :description)},
          Keyword.get(opts, :metadata, %{})
        )
    }
  end

  @doc """
  Validate data against a schema.

  ## Examples

      iex> ElixirML.Schema.validate(MySchema, %{field: "value"})
      {:ok, %{field: "value"}}

      iex> ElixirML.Schema.validate(MySchema, %{invalid: "data"})
      {:error, %ElixirML.Schema.ValidationError{}}
  """
  @spec validate(module() | Runtime.t(), map()) ::
          {:ok, map()} | {:error, ElixirML.Schema.ValidationError.t()}
  def validate(schema_module, data) when is_atom(schema_module) do
    schema_module.validate(data)
  end

  def validate(%Runtime{} = schema, data) do
    Runtime.validate(schema, data)
  end

  @doc """
  Extract variables from a schema for optimization.
  """
  @spec extract_variables(module()) :: list()
  def extract_variables(schema_module) when is_atom(schema_module) do
    schema_module.__variables__()
  end

  @doc """
  Generate JSON schema representation with optional provider optimization.

  ## Options

  - `:provider` - Optimize for specific LLM provider (`:openai`, `:anthropic`, `:groq`)
  - `:flatten` - Flatten schema references (default: `false`)
  - `:include_descriptions` - Include field descriptions (default: `true`)

  ## Examples

      iex> ElixirML.Schema.to_json_schema(MySchema, provider: :openai)
      %{
        "type" => "object",
        "properties" => %{...},
        "additionalProperties" => false
      }
  """
  @spec to_json_schema(module() | Runtime.t(), keyword()) :: map()
  def to_json_schema(schema_or_module, opts \\ [])

  def to_json_schema(schema_module, opts) when is_atom(schema_module) do
    provider = Keyword.get(opts, :provider, :generic)
    include_descriptions = Keyword.get(opts, :include_descriptions, true)

    # Get base JSON schema from compiled module
    base_schema = schema_module.to_json_schema()

    # Apply provider-specific optimizations
    base_schema
    |> apply_ml_optimizations()
    |> apply_provider_optimizations(provider)
    |> maybe_include_descriptions(include_descriptions)
  end

  def to_json_schema(%Runtime{} = schema, opts) do
    Runtime.to_json_schema(schema, opts)
  end

  @doc """
  Optimize a schema for a specific LLM provider.

  ## Examples

      iex> optimized = ElixirML.Schema.optimize_for_provider(schema, :openai)
      %ElixirML.Schema.Runtime{metadata: %{provider_optimizations: :openai}}
  """
  @spec optimize_for_provider(Runtime.t(), atom()) :: Runtime.t()
  def optimize_for_provider(%Runtime{} = schema, provider) do
    %{schema | metadata: Map.put(schema.metadata, :provider_optimizations, provider)}
  end

  @doc """
  Create a schema using the Pydantic create_model pattern.

  ## Examples

      iex> fields = %{
      ...>   reasoning: {:string, description: "Chain of thought"},
      ...>   answer: {:string, required: true},
      ...>   confidence: {:float, gteq: 0.0, lteq: 1.0}
      ...> }
      iex> schema = ElixirML.Schema.create_model("LLMOutput", fields)
      %ElixirML.Schema.Runtime{name: "LLMOutput"}
  """
  @spec create_model(String.t(), map(), keyword()) :: Runtime.t()
  def create_model(name, fields, opts \\ []) do
    # Convert Pydantic-style fields to ElixirML format
    converted_fields =
      fields
      |> Enum.map(&convert_pydantic_field/1)
      |> List.flatten()

    # Convert list of tuples to map for easier access in tests
    fields_map =
      converted_fields
      |> Enum.map(fn {name, type, opts} -> {name, %{type: type, opts: opts}} end)
      |> Map.new()

    %Runtime{
      name: name,
      fields: converted_fields,
      validations: Keyword.get(opts, :validations, []),
      transforms: Keyword.get(opts, :transforms, []),
      metadata:
        Map.merge(
          %{created_with: :create_model, fields_map: fields_map},
          Keyword.get(opts, :metadata, %{})
        )
    }
  end

  @doc """
  Create a type adapter for single value validation.

  ## Examples

      iex> adapter = ElixirML.Schema.type_adapter(:probability, range: {0.0, 1.0})
      iex> ElixirML.Schema.validate_with_adapter(adapter, 0.75)
      {:ok, 0.75}
  """
  @spec type_adapter(atom(), keyword()) :: map()
  def type_adapter(type, opts \\ []) do
    %{
      type: type,
      constraints: extract_constraints(opts),
      metadata: %{adapter_type: :single_value}
    }
  end

  @doc """
  Validate a value using a type adapter.
  """
  @spec validate_with_adapter(map(), any()) :: {:ok, any()} | {:error, term()}
  def validate_with_adapter(%{type: type, constraints: _constraints}, value) do
    case ElixirML.Schema.Types.validate_type(value, type) do
      {:ok, validated} ->
        # TODO: Apply constraint validation
        {:ok, validated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp apply_ml_optimizations(schema) when is_map(schema) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        optimized_props =
          properties
          |> Enum.map(fn {key, prop} -> {key, optimize_ml_property(prop)} end)
          |> Map.new()

        Map.put(schema, "properties", optimized_props)
    end
  end

  defp optimize_ml_property(%{"x-elixir-type" => :embedding} = prop) do
    dimension = get_in(prop, ["x-constraints", "dimension"]) || 768

    Map.merge(prop, %{
      "type" => "array",
      "items" => %{"type" => "number"},
      "minItems" => dimension,
      "maxItems" => dimension,
      "description" => "Vector embedding with #{dimension} dimensions"
    })
  end

  defp optimize_ml_property(%{"x-elixir-type" => :probability} = prop) do
    Map.merge(prop, %{
      "type" => "number",
      "minimum" => 0.0,
      "maximum" => 1.0,
      "description" => "Probability value between 0.0 and 1.0"
    })
  end

  defp optimize_ml_property(%{"x-elixir-type" => :confidence_score} = prop) do
    Map.merge(prop, %{
      "type" => "number",
      "minimum" => 0.0,
      "description" => "Non-negative confidence score"
    })
  end

  defp optimize_ml_property(%{"x-elixir-type" => :token_list} = prop) do
    Map.merge(prop, %{
      "type" => "array",
      "items" => %{
        "oneOf" => [
          %{"type" => "string"},
          %{"type" => "integer"}
        ]
      },
      "description" => "List of tokens (strings or integers)"
    })
  end

  defp optimize_ml_property(%{"x-elixir-type" => :reasoning_chain} = prop) do
    Map.merge(prop, %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "step" => %{"type" => "string"},
          "reasoning" => %{"type" => "string"}
        },
        "required" => ["step", "reasoning"]
      },
      "description" => "Chain of reasoning steps"
    })
  end

  defp optimize_ml_property(prop), do: prop

  defp apply_provider_optimizations(schema, :openai) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array()
    |> remove_unsupported_formats([:date, :time, :email])
    |> add_openai_metadata()
  end

  defp apply_provider_optimizations(schema, :anthropic) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array()
    |> remove_unsupported_formats([:uri, :uuid])
    |> ensure_object_properties()
    |> add_anthropic_metadata()
  end

  defp apply_provider_optimizations(schema, :groq) do
    schema
    |> Map.put("additionalProperties", false)
    |> ensure_required_array()
    |> add_groq_metadata()
  end

  defp apply_provider_optimizations(schema, _), do: schema

  defp ensure_required_array(schema) do
    case Map.get(schema, "required") do
      nil -> Map.put(schema, "required", [])
      list when is_list(list) -> schema
      _ -> Map.put(schema, "required", [])
    end
  end

  defp remove_unsupported_formats(schema, unsupported_formats) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        updated_properties =
          properties
          |> Enum.map(fn {key, prop} ->
            case Map.get(prop, "format") do
              format when is_atom(format) ->
                if format in unsupported_formats do
                  {key, Map.delete(prop, "format")}
                else
                  {key, prop}
                end

              _ ->
                {key, prop}
            end
          end)
          |> Map.new()

        Map.put(schema, "properties", updated_properties)
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

  defp add_openai_metadata(schema) do
    Map.put(schema, "x-openai-optimized", true)
  end

  defp add_anthropic_metadata(schema) do
    Map.put(schema, "x-anthropic-optimized", true)
  end

  defp add_groq_metadata(schema) do
    Map.put(schema, "x-groq-optimized", true)
  end

  defp maybe_include_descriptions(schema, true), do: schema

  defp maybe_include_descriptions(schema, false) do
    case Map.get(schema, "properties") do
      nil ->
        schema

      properties ->
        updated_properties =
          properties
          |> Enum.map(fn {key, prop} -> {key, Map.delete(prop, "description")} end)
          |> Map.new()

        schema
        |> Map.put("properties", updated_properties)
        |> Map.delete("description")
    end
  end

  defp convert_pydantic_field({field_name, {type, opts}}) do
    constraints = extract_pydantic_constraints(opts)
    required = Keyword.get(opts, :required, false)
    default = Keyword.get(opts, :default)
    description = Keyword.get(opts, :description)

    field_opts = [required: required]
    field_opts = if default, do: Keyword.put(field_opts, :default, default), else: field_opts

    field_opts =
      if description, do: Keyword.put(field_opts, :description, description), else: field_opts

    field_opts = Keyword.merge(field_opts, constraints)

    {field_name, type, field_opts}
  end

  defp convert_pydantic_field({field_name, type}) when is_atom(type) do
    {field_name, type, []}
  end

  defp extract_pydantic_constraints(opts) when is_list(opts) do
    opts
    |> Enum.filter(fn {key, _} ->
      key in [:gteq, :lteq, :gt, :lt, :min_length, :max_length, :regex, :dimension, :range]
    end)
  end

  defp extract_constraints(opts) when is_list(opts) do
    opts
    |> Enum.filter(fn {key, _} ->
      key in [
        :min,
        :max,
        :gteq,
        :lteq,
        :gt,
        :lt,
        :min_length,
        :max_length,
        :regex,
        :dimension,
        :range
      ]
    end)
    |> Map.new()
  end
end
