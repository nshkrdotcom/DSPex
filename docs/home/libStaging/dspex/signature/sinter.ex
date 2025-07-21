defmodule DSPEx.Signature.Sinter do
  @moduledoc """
  Bridge module between DSPEx signatures and Sinter schema validation.

  This module provides conversion utilities to translate DSPEx signature
  definitions into Sinter schemas for enhanced validation, type safety,
  and JSON schema generation.

  ## Key Features

  - Convert DSPEx signatures to Sinter schemas
  - Validate inputs/outputs using Sinter validation
  - Generate JSON schemas from DSPEx signatures
  - Maintain backward compatibility with existing signature system
  - Enhanced error reporting with field-level validation details

  ## Usage

      # Convert existing DSPEx signature to Sinter schema
      defmodule QASignature do
        use DSPEx.Signature, "question -> answer"
      end

      # Generate Sinter schema
      schema = DSPEx.Signature.Sinter.signature_to_schema(QASignature)

      # Validate data using Sinter
      {:ok, validated} = DSPEx.Signature.Sinter.validate_with_sinter(QASignature, %{
        question: "What is 2+2?"
      })

      # Generate JSON schema
      json_schema = DSPEx.Signature.Sinter.generate_json_schema(QASignature)

  ## Enhanced Validation

  The bridge supports enhanced field definitions through options:

      defmodule EnhancedSignature do
        use DSPEx.Signature, "question:string[min_length=1,max_length=500] -> answer:string[max_length=1000]"
      end

  """

  @type signature_module :: module()
  @type field_constraints :: %{
          optional(:min_length) => non_neg_integer(),
          optional(:max_length) => non_neg_integer(),
          optional(:min_items) => non_neg_integer(),
          optional(:max_items) => non_neg_integer(),
          optional(:format) => Regex.t(),
          optional(:choices) => [term()],
          optional(:gteq) => number(),
          optional(:lteq) => number(),
          optional(:gt) => number(),
          optional(:lt) => number()
        }

  @doc """
  Converts a DSPEx signature module to a Sinter schema definition.

  This function analyzes the signature's input and output fields and creates
  an equivalent Sinter schema that can be used for enhanced validation.

  ## Parameters

  - `signature` - The DSPEx signature module to convert

  ## Returns

  - `schema` - Generated Sinter schema structure
  - Raises exception if conversion fails

  ## Examples

      iex> defmodule TestSignature do
      ...>   use DSPEx.Signature, "name -> greeting"
      ...> end
      iex> schema = DSPEx.Signature.Sinter.signature_to_schema(TestSignature)
      iex> is_map(schema)
      true

  """
  @spec signature_to_schema(signature_module()) :: map()
  def signature_to_schema(signature) when is_atom(signature) do
    with :ok <- validate_signature_module(signature),
         field_definitions <- extract_field_definitions(signature) do
      generate_sinter_schema(signature, field_definitions)
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
  Validates data against a DSPEx signature using Sinter validation.

  This function converts the signature to a Sinter schema and validates
  the provided data, returning enhanced error information if validation fails.

  ## Parameters

  - `signature` - The DSPEx signature module
  - `data` - The data to validate (typically inputs or outputs)
  - `opts` - Optional validation options

  ## Options

  - `:field_type` - `:inputs` (default) or `:outputs` to validate specific field types
  - `:strict` - Boolean to enable strict validation (default: false)

  ## Returns

  - `{:ok, validated_data}` - Successfully validated data
  - `{:error, validation_errors}` - Detailed validation errors

  ## Examples

      iex> defmodule SimpleSignature do
      ...>   use DSPEx.Signature, "name -> greeting"
      ...> end
      iex> {:ok, validated} = DSPEx.Signature.Sinter.validate_with_sinter(SimpleSignature, %{name: "Alice"})
      iex> validated.name
      "Alice"

  """
  @spec validate_with_sinter(signature_module(), map(), keyword()) ::
          {:ok, map()} | {:error, [map()]}
  def validate_with_sinter(signature, data, opts \\ [])
      when is_atom(signature) and is_map(data) do
    field_type = Keyword.get(opts, :field_type, :inputs)

    schema = signature_to_schema_for_field_type(signature, field_type)
    filtered_data = filter_data_by_field_type(signature, data, field_type)

    case Sinter.Validator.validate(schema, filtered_data) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, errors} -> {:error, normalize_sinter_errors(errors)}
    end
  rescue
    error -> {:error, [{:validation_failed, inspect(error)}]}
  end

  @doc """
  Generates a JSON Schema from a DSPEx signature.

  This function converts the signature to a Sinter schema and then
  generates a JSON Schema representation, useful for API documentation
  and client-side validation.

  ## Parameters

  - `signature` - The DSPEx signature module
  - `opts` - Optional generation options

  ## Options

  - `:field_type` - `:inputs`, `:outputs`, or `:all` (default)
  - `:provider` - `:openai`, `:anthropic`, or `:generic` (default)
  - `:title` - Custom title for the schema
  - `:description` - Custom description for the schema

  ## Returns

  - JSON Schema as a map

  ## Examples

      iex> defmodule JsonSignature do
      ...>   use DSPEx.Signature, "question -> answer"
      ...> end
      iex> json_schema = DSPEx.Signature.Sinter.generate_json_schema(JsonSignature)
      iex> json_schema["type"]
      "object"

  """
  @spec generate_json_schema(signature_module(), keyword()) :: map()
  def generate_json_schema(signature, opts \\ []) when is_atom(signature) do
    schema = signature_to_schema(signature)
    provider = Keyword.get(opts, :provider, :generic)

    json_schema =
      case provider do
        :generic -> Sinter.JsonSchema.generate(schema)
        provider_atom -> Sinter.JsonSchema.for_provider(schema, provider_atom)
      end

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

    enhanced_fields = get_enhanced_fields(signature)

    case enhanced_signature_available?(signature) do
      true -> extract_from_enhanced_parser(signature)
      false -> extract_from_field_mapping(signature, input_fields, output_fields, enhanced_fields)
    end
  end

  defp get_enhanced_fields(signature) do
    if function_exported?(signature, :__enhanced_fields__, 0) do
      signature.__enhanced_fields__()
    else
      []
    end
  end

  defp enhanced_signature_available?(signature) do
    function_exported?(signature, :__signature_string__, 0) and
      DSPEx.Signature.EnhancedParser.enhanced_signature?(signature.__signature_string__())
  end

  defp extract_from_enhanced_parser(signature) do
    {parsed_inputs, parsed_outputs} =
      DSPEx.Signature.EnhancedParser.parse(signature.__signature_string__())

    parsed_inputs ++ parsed_outputs
  end

  defp extract_from_field_mapping(_signature, input_fields, output_fields, enhanced_fields) do
    all_fields = input_fields ++ output_fields
    field_map = Enum.into(enhanced_fields, %{}, fn field -> {field.name, field} end)

    Enum.map(all_fields, fn field_name ->
      build_field_definition(field_name, field_map, input_fields)
    end)
  end

  defp build_field_definition(field_name, field_map, input_fields) do
    case Map.get(field_map, field_name) do
      nil -> build_basic_field(field_name, input_fields)
      enhanced_field -> build_enhanced_field(enhanced_field, input_fields)
    end
  end

  defp build_basic_field(field_name, input_fields) do
    %{
      name: field_name,
      type: :string,
      constraints: %{},
      required: field_name in input_fields,
      default: nil
    }
  end

  defp build_enhanced_field(enhanced_field, input_fields) do
    %{
      name: enhanced_field.name,
      type: enhanced_field.type || :string,
      constraints: enhanced_field.constraints || %{},
      required: enhanced_field.name in input_fields,
      default: Map.get(enhanced_field, :default)
    }
  end

  defp generate_sinter_schema(signature, field_definitions) do
    # Convert field definitions to Sinter schema format
    sinter_fields =
      Enum.map(field_definitions, fn field_def ->
        {
          field_def.name,
          field_def.type,
          build_sinter_constraints(field_def)
        }
      end)

    # Create schema with metadata
    Sinter.Schema.define(sinter_fields,
      title: extract_signature_title(signature),
      description: extract_signature_description(signature)
    )
  end

  defp build_sinter_constraints(field_def) do
    base_constraints = if field_def.required, do: [required: true], else: [optional: true]

    constraint_list =
      field_def.constraints
      |> Enum.reduce(base_constraints, fn {key, value}, acc ->
        case map_constraint_to_sinter(key, value) do
          {sinter_key, sinter_value} -> Keyword.put(acc, sinter_key, sinter_value)
          nil -> acc
        end
      end)

    # Add default if present
    if field_def.default do
      Keyword.put(constraint_list, :default, field_def.default)
    else
      constraint_list
    end
  end

  defp map_constraint_to_sinter(:min_length, value), do: {:min_length, value}
  defp map_constraint_to_sinter(:max_length, value), do: {:max_length, value}
  defp map_constraint_to_sinter(:min_items, value), do: {:min_items, value}
  defp map_constraint_to_sinter(:max_items, value), do: {:max_items, value}
  defp map_constraint_to_sinter(:gteq, value), do: {:gteq, value}
  defp map_constraint_to_sinter(:lteq, value), do: {:lteq, value}
  defp map_constraint_to_sinter(:gt, value), do: {:gt, value}
  defp map_constraint_to_sinter(:lt, value), do: {:lt, value}
  defp map_constraint_to_sinter(:format, value), do: {:format, value}
  defp map_constraint_to_sinter(:choices, value), do: {:choices, value}
  defp map_constraint_to_sinter(_key, _value), do: nil

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

    generate_sinter_schema(signature, filtered_fields)
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

  defp normalize_sinter_errors(errors) when is_list(errors) do
    Enum.map(errors, &normalize_single_error/1)
  end

  defp normalize_single_error(%Sinter.Error{} = error) do
    %{
      path: error.path,
      code: error.code,
      message: error.message,
      context: error.context || %{}
    }
  end

  defp normalize_single_error(error) when is_map(error) do
    error
  end

  defp normalize_single_error(error) do
    %{message: inspect(error)}
  end

  defp extract_signature_title(signature) do
    if function_exported?(signature, :__signature_title__, 0) do
      signature.__signature_title__()
    else
      signature |> Module.split() |> List.last()
    end
  end

  defp extract_signature_description(signature) do
    if function_exported?(signature, :__signature_description__, 0) do
      signature.__signature_description__()
    else
      "DSPEx signature: #{inspect(signature)}"
    end
  end

  defp customize_json_schema(json_schema, signature, opts) do
    json_schema
    |> maybe_add_title(opts[:title] || extract_signature_title(signature))
    |> maybe_add_description(opts[:description] || extract_signature_description(signature))
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
