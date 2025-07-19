defmodule DSPEx.Schema do
  @moduledoc """
  Bridge between DSPEx signatures and ElixirML schemas.

  Replaces DSPEx.Signature.Sinter with ElixirML-based validation.
  Provides seamless integration between DSPEx signature definitions
  and the ElixirML schema system with ML-specific types and optimization.

  ## Key Features

  - Convert DSPEx signatures to ElixirML schemas
  - Validate inputs/outputs using ElixirML validation with ML-native types
  - Generate JSON schemas optimized for different LLM providers
  - Extract variables for optimization systems
  - Maintain backward compatibility with existing DSPEx patterns
  - Enhanced error reporting with field-level validation details

  ## Usage

      # Convert existing DSPEx signature to ElixirML schema
      defmodule QASignature do
        use DSPEx.Signature, "question:string -> answer:string"
      end

      # Generate ElixirML schema
      schema = DSPEx.Schema.signature_to_schema(QASignature)

      # Validate data using ElixirML
      {:ok, validated} = DSPEx.Schema.validate_with_elixir_ml(QASignature, %{
        question: "What is 2+2?"
      })

      # Generate optimized JSON schema
      json_schema = DSPEx.Schema.generate_json_schema(QASignature, provider: :openai)

  ## Enhanced Validation with ML Types

  The bridge supports ML-specific types and enhanced field definitions:

      defmodule MLSignature do
        use DSPEx.Signature, "context:string[min_length=10], question:string -> answer:string, confidence:probability, reasoning:string[max_length=500]"
      end

  """

  alias ElixirML.Runtime

  @type signature_module :: module()
  @type validation_opts :: [
          field_type: :inputs | :outputs | :all,
          strict: boolean()
        ]

  @doc """
  Converts a DSPEx signature module to an ElixirML schema.

  This function analyzes the signature's input and output fields and creates
  an equivalent ElixirML schema that can be used for enhanced validation
  with ML-specific types and provider optimizations.

  ## Parameters

  - `signature` - The DSPEx signature module to convert

  ## Returns

  - `ElixirML.Runtime` schema structure
  - Raises exception if conversion fails

  ## Examples

      iex> defmodule TestSignature do
      ...>   use DSPEx.Signature, "name:string -> greeting:string"
      ...> end
      iex> schema = DSPEx.Schema.signature_to_schema(TestSignature)
      iex> %ElixirML.Runtime{} = schema
      true

  """
  @spec signature_to_schema(signature_module()) :: Runtime.t()
  def signature_to_schema(signature) when is_atom(signature) do
    with :ok <- validate_signature_module(signature),
         field_definitions <- extract_field_definitions(signature) do
      generate_elixir_ml_schema(signature, field_definitions)
    else
      {:error, reason} -> raise ArgumentError, "Failed to convert signature: #{inspect(reason)}"
    end
  rescue
    error ->
      reraise ArgumentError,
              [message: "Signature conversion failed: #{inspect(error)}"],
              __STACKTRACE__
  end

  @doc """
  Validates data against a DSPEx signature using ElixirML validation.

  This function converts the signature to an ElixirML schema and validates
  the provided data with ML-native type support and enhanced error information.

  ## Parameters

  - `signature` - The DSPEx signature module
  - `data` - The data to validate (typically inputs or outputs)
  - `opts` - Optional validation options

  ## Options

  - `:field_type` - `:inputs` (default), `:outputs`, or `:all` to validate specific fields
  - `:strict` - Boolean to enable strict validation (default: false)

  ## Returns

  - `{:ok, validated_data}` - Successfully validated data
  - `{:error, validation_errors}` - Detailed validation errors

  ## Examples

      iex> defmodule SimpleSignature do
      ...>   use DSPEx.Signature, "name:string -> greeting:string"
      ...> end
      iex> {:ok, validated} = DSPEx.Schema.validate_with_elixir_ml(SimpleSignature, %{name: "Alice"})
      iex> validated.name
      "Alice"

  """
  @spec validate_with_elixir_ml(signature_module(), map(), validation_opts()) ::
          {:ok, map()} | {:error, [map()]}
  def validate_with_elixir_ml(signature, data, opts \\ [])
      when is_atom(signature) and is_map(data) do
    field_type = Keyword.get(opts, :field_type, :inputs)

    schema = signature_to_schema_for_field_type(signature, field_type)
    filtered_data = filter_data_by_field_type(signature, data, field_type)

    case Runtime.validate(schema, filtered_data) do
      {:ok, validated_data} ->
        {:ok, validated_data}
        # Note: Based on dialyzer analysis, Runtime.validate always returns {:ok, map()}
        # Removed unreachable error handling pattern
    end
  rescue
    error -> {:error, [%{message: "Validation failed: #{inspect(error)}"}]}
  end

  @doc """
  Generates a JSON Schema from a DSPEx signature.

  This function converts the signature to an ElixirML schema and then
  generates a JSON Schema representation with provider-specific optimizations,
  useful for API documentation and client-side validation.

  ## Parameters

  - `signature` - The DSPEx signature module
  - `opts` - Optional generation options

  ## Options

  - `:field_type` - `:inputs`, `:outputs`, or `:all` (default)
  - `:provider` - `:openai`, `:anthropic`, `:groq`, or `:generic` (default)
  - `:title` - Custom title for the schema
  - `:description` - Custom description for the schema

  ## Returns

  - JSON Schema as a map with provider-specific optimizations

  ## Examples

      iex> defmodule JsonSignature do
      ...>   use DSPEx.Signature, "question:string -> answer:string"
      ...> end
      iex> json_schema = DSPEx.Schema.generate_json_schema(JsonSignature, provider: :openai)
      iex> json_schema["type"]
      "object"

  """
  @spec generate_json_schema(signature_module(), keyword()) :: map()
  def generate_json_schema(signature, opts \\ []) when is_atom(signature) do
    field_type = Keyword.get(opts, :field_type, :all)
    provider = Keyword.get(opts, :provider, :generic)

    schema = signature_to_schema_for_field_type(signature, field_type)

    json_schema = Runtime.to_json_schema(schema, provider: provider)

    # Customize the schema based on options
    customize_json_schema(json_schema, signature, opts)
  rescue
    error ->
      # Fallback to basic schema
      %{
        "type" => "object",
        "properties" => %{},
        "error" => "Schema generation failed: #{inspect(error)}"
      }
  end

  @doc """
  Extracts variables from a DSPEx signature for optimization.

  This function converts the signature to an ElixirML schema and extracts
  any fields marked as variables for use with optimization systems.

  ## Parameters

  - `signature` - The DSPEx signature module

  ## Returns

  - List of variable specifications for optimization

  ## Examples

      iex> variables = DSPEx.Schema.extract_variables(MySignature)
      iex> is_list(variables)
      true

  """
  @spec extract_variables(signature_module()) :: [tuple()]
  def extract_variables(signature) when is_atom(signature) do
    schema = signature_to_schema(signature)
    Runtime.extract_variables(schema)
  rescue
    _error -> []
  end

  ## Private helper functions

  defp validate_signature_module(signature) do
    cond do
      not Code.ensure_loaded?(signature) ->
        {:error, {:module_not_loaded, signature}}

      not function_exported?(signature, :input_fields, 0) ->
        {:error, {:not_signature_module, signature}}

      true ->
        :ok
    end
  end

  defp extract_field_definitions(signature) do
    input_fields = signature.input_fields()
    output_fields = signature.output_fields()

    case enhanced_fields_available?(signature) do
      true -> extract_from_enhanced_fields(signature, input_fields, output_fields)
      false -> extract_from_basic_fields(signature, input_fields, output_fields)
    end
  end

  defp enhanced_fields_available?(signature) do
    function_exported?(signature, :__enhanced_fields__, 0)
  end

  defp extract_from_enhanced_fields(signature, input_fields, _output_fields) do
    enhanced_fields = signature.__enhanced_fields__()

    Enum.map(enhanced_fields, fn enhanced_field ->
      convert_enhanced_field_to_elixir_ml(enhanced_field, enhanced_field.name in input_fields)
    end)
  end

  defp extract_from_basic_fields(_signature, input_fields, output_fields) do
    all_fields = input_fields ++ output_fields

    Enum.map(all_fields, fn field_name ->
      build_basic_field_definition(field_name, field_name in input_fields)
    end)
  end

  defp convert_enhanced_field_to_elixir_ml(enhanced_field, is_input) do
    %{
      name: enhanced_field.name,
      type: map_type_to_elixir_ml(enhanced_field.type),
      constraints: convert_constraints_to_elixir_ml(enhanced_field.constraints),
      # Only inputs are required for validation
      required: is_input,
      default: Map.get(enhanced_field, :default),
      description: Map.get(enhanced_field, :description),
      variable: Map.get(enhanced_field, :variable, false)
    }
  end

  defp build_basic_field_definition(field_name, is_input) do
    %{
      name: field_name,
      # Default type for basic fields
      type: :string,
      constraints: %{},
      # Only inputs are required by default
      required: is_input,
      default: nil,
      description: nil,
      variable: false
    }
  end

  defp map_type_to_elixir_ml(nil), do: :string
  defp map_type_to_elixir_ml(:string), do: :string
  defp map_type_to_elixir_ml(:integer), do: :integer
  defp map_type_to_elixir_ml(:float), do: :float
  defp map_type_to_elixir_ml(:boolean), do: :boolean
  defp map_type_to_elixir_ml(:probability), do: :probability
  defp map_type_to_elixir_ml(:confidence), do: :confidence_score
  defp map_type_to_elixir_ml(:embedding), do: :embedding
  defp map_type_to_elixir_ml(:tokens), do: :token_list
  defp map_type_to_elixir_ml(:reasoning), do: :reasoning_chain
  defp map_type_to_elixir_ml(:list), do: :list
  defp map_type_to_elixir_ml(:map), do: :map
  defp map_type_to_elixir_ml(type) when is_atom(type), do: type
  defp map_type_to_elixir_ml(_), do: :string

  defp convert_constraints_to_elixir_ml(constraints) when is_map(constraints) do
    constraints
    |> Enum.map(&convert_single_constraint/1)
    |> Enum.filter(& &1)
    |> Map.new()
  end

  defp convert_constraints_to_elixir_ml(_), do: %{}

  defp convert_single_constraint({:min_length, value}), do: {:min_length, value}
  defp convert_single_constraint({:max_length, value}), do: {:max_length, value}
  defp convert_single_constraint({:min_items, value}), do: {:min_items, value}
  defp convert_single_constraint({:max_items, value}), do: {:max_items, value}
  defp convert_single_constraint({:gteq, value}), do: {:min_value, value}
  defp convert_single_constraint({:lteq, value}), do: {:max_value, value}
  defp convert_single_constraint({:gt, value}), do: {:min_value, value + 0.001}
  defp convert_single_constraint({:lt, value}), do: {:max_value, value - 0.001}
  defp convert_single_constraint({:format, value}), do: {:pattern, value}
  defp convert_single_constraint({:choices, value}), do: {:choices, value}
  defp convert_single_constraint({:range, {min, max}}), do: {:range, {min, max}}
  defp convert_single_constraint({:dimension, value}), do: {:dimensions, value}
  defp convert_single_constraint(_), do: nil

  defp generate_elixir_ml_schema(signature, field_definitions) do
    # Convert field definitions to ElixirML format
    elixir_ml_fields =
      Enum.map(field_definitions, fn field_def ->
        opts = build_field_opts(field_def)
        {field_def.name, field_def.type, opts}
      end)

    # Create ElixirML runtime schema
    Runtime.create_schema(elixir_ml_fields,
      title: extract_signature_title(signature),
      name: extract_signature_name(signature),
      metadata: %{
        source_signature: signature,
        created_with: :dspex_bridge,
        created_at: DateTime.utc_now()
      }
    )
  end

  defp build_field_opts(field_def) do
    base_opts = [
      required: field_def.required,
      description: field_def.description,
      variable: field_def.variable
    ]

    constraint_opts =
      field_def.constraints
      |> Enum.to_list()

    default_opts =
      if field_def.default, do: [default: field_def.default], else: []

    base_opts
    |> Keyword.merge(constraint_opts)
    |> Keyword.merge(default_opts)
    |> Enum.filter(fn {_k, v} -> not is_nil(v) end)
  end

  defp signature_to_schema_for_field_type(signature, field_type) do
    field_definitions = extract_field_definitions(signature)

    filtered_fields =
      case field_type do
        :inputs ->
          input_fields = signature.input_fields()
          Enum.filter(field_definitions, fn field -> field.name in input_fields end)

        :outputs ->
          output_fields = signature.output_fields()
          Enum.filter(field_definitions, fn field -> field.name in output_fields end)

        :all ->
          field_definitions
      end

    generate_elixir_ml_schema(signature, filtered_fields)
  end

  defp filter_data_by_field_type(signature, data, field_type) do
    case field_type do
      :inputs ->
        input_fields = signature.input_fields()
        Map.take(data, input_fields)

      :outputs ->
        output_fields = signature.output_fields()
        Map.take(data, output_fields)

      :all ->
        data
    end
  end

  defp extract_signature_title(signature) do
    if function_exported?(signature, :__signature_title__, 0) do
      signature.__signature_title__()
    else
      signature |> Module.split() |> List.last()
    end
  end

  defp extract_signature_name(signature) do
    signature |> Module.split() |> List.last()
  end

  defp customize_json_schema(json_schema, signature, opts) do
    json_schema
    |> maybe_add_title(opts[:title] || extract_signature_title(signature))
    |> maybe_add_description(opts[:description] || "DSPEx signature: #{inspect(signature)}")
    |> maybe_filter_by_field_type(signature, opts[:field_type])
  end

  defp maybe_add_title(schema, nil), do: schema
  defp maybe_add_title(schema, title), do: Map.put(schema, "title", title)

  defp maybe_add_description(schema, nil), do: schema
  defp maybe_add_description(schema, description), do: Map.put(schema, "description", description)

  defp maybe_filter_by_field_type(schema, _signature, nil), do: schema
  defp maybe_filter_by_field_type(schema, _signature, :all), do: schema

  defp maybe_filter_by_field_type(schema, signature, field_type) do
    # Filter properties based on field type
    target_fields =
      case field_type do
        :inputs -> signature.input_fields()
        :outputs -> signature.output_fields()
      end

    properties = Map.get(schema, "properties", %{})
    filtered_properties = Map.take(properties, Enum.map(target_fields, &Atom.to_string/1))

    schema
    |> Map.put("properties", filtered_properties)
    |> Map.update("required", [], fn required ->
      string_fields = Enum.map(target_fields, &Atom.to_string/1)
      Enum.filter(required, &(&1 in string_fields))
    end)
  end
end
